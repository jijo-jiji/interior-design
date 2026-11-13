"""Trains the wall-corner model on synthetic rooms.

    python tool/wall_corner_training/train.py OUT_DIR [--steps 12000] [--resume]

Writes OUT_DIR/corner.pt (checkpoint), OUT_DIR/log.txt and, at the end,
OUT_DIR/wall_corners.onnx for the app. Needs torch, numpy and onnx. Uses the
graphics card if torch was built with CUDA, else the processor. On the
graphics card, making the samples is the slow part: give it more --workers.
"""
import argparse
import math
import sys
import time
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader, IterableDataset, get_worker_info

sys.path.insert(0, str(Path(__file__).parent))
import synth  # noqa: E402
from model import CornerNet, Exported, init_from  # noqa: E402


class Rooms(IterableDataset):
    """An endless stream of fresh synthetic samples, each also mirrored."""

    def __init__(self, seed: int):
        self.seed = seed

    def __iter__(self):
        info = get_worker_info()
        torch.set_num_threads(1)
        rng = np.random.default_rng([self.seed, info.id if info else 0])
        while True:
            x, y, _ = synth.sample(rng)
            yield torch.from_numpy(x), torch.from_numpy(y)
            mx, my = synth.mirror(x, y)
            yield torch.from_numpy(mx), torch.from_numpy(my)


def fixed_set(seed: int, count: int):
    rng = np.random.default_rng(seed)
    xs, ys, ks = zip(*(synth.sample(rng) for _ in range(count)))
    return torch.from_numpy(np.stack(xs)), torch.from_numpy(np.stack(ys)), np.array(ks)


def corner_errors(pred: torch.Tensor, truth: torch.Tensor) -> np.ndarray:
    """Distance of each point from the truth, in fractions of the photo: (N, points)."""
    d = (pred - truth).reshape(pred.shape[0], -1, 2)
    return d.pow(2).sum(-1).sqrt().numpy()


def validate(net, vx, vy, vk, device) -> str:
    net.eval()
    with torch.no_grad():
        preds, logs = zip(*(tuple(o.cpu() for o in net(vx[i:i + 256].to(device)))
                            for i in range(0, len(vx), 256)))
    net.train()
    pred, log_err = torch.cat(preds), torch.cat(logs)
    # The four corners as marked (what the salesperson sees), and the two
    # hidden bottom corners (what the app measures with) apart.
    err = corner_errors(pred[:, :8], vy[:, :8])
    hidden = corner_errors(pred[:, 8:], vy[:, 8:])
    worst = err.max(1)
    # Does the model know when it's wrong? Keep the half it's surest of.
    sure = log_err[:, :8].exp().max(1).values.numpy()
    keep = sure <= np.median(sure)
    parts = [f"median {np.median(err) * 100:.2f}%", f"90th {np.percentile(err, 90) * 100:.2f}%",
             f"kitchens {np.median(err[vk]) * 100:.2f}%", f"rooms {np.median(err[~vk]) * 100:.2f}%",
             f"worst corner: all {np.median(worst) * 100:.2f}%, surest half {np.median(worst[keep]) * 100:.2f}%",
             f"hidden bottom corners {np.median(hidden) * 100:.2f}%"]
    return ", ".join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--steps", type=int, default=12000)
    ap.add_argument("--batch", type=int, default=64)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--init", help="start from this checkpoint's weights (corner.pt), as a new run")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    log = open(out / "log.txt", "a", encoding="utf-8")

    def say(msg):
        print(msg, flush=True)
        log.write(msg + "\n")
        log.flush()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    gpu = device.type == "cuda"
    if gpu:
        torch.backends.cudnn.benchmark = True
    net = CornerNet().to(device)
    opt = torch.optim.AdamW(net.parameters(), lr=args.lr, weight_decay=1e-4)
    start = 0
    if args.init and not (args.resume and (out / "corner.pt").exists()):
        init_from(net, torch.load(args.init, map_location=device, weights_only=True)["net"])
        say(f"started from the weights in {args.init}")
    if args.resume and (out / "corner.pt").exists():
        state = torch.load(out / "corner.pt", map_location=device, weights_only=True)
        net.load_state_dict(state["net"])
        opt.load_state_dict(state["opt"])
        start = state["step"]
        say(f"resumed at step {start}")
    where = torch.cuda.get_device_name(device) if gpu else "the processor"
    say(f"{sum(p.numel() for p in net.parameters()) / 1e6:.2f} M weights, on {where}, "
        f"{args.workers} workers; making the validation set ...")
    vx, vy, vk = fixed_set(seed=20261111, count=1024)
    loader = iter(DataLoader(Rooms(seed=7 + start), batch_size=args.batch, num_workers=args.workers,
                             pin_memory=gpu))

    t0 = time.time()
    running = 0.0
    for step in range(start + 1, args.steps + 1):
        lr = args.lr * (min(1.0, step / 300) * 0.5 * (1 + math.cos(math.pi * step / args.steps)) + 0.01)
        for g in opt.param_groups:
            g["lr"] = lr
        x, y = next(loader)
        x, y = x.to(device, non_blocking=True), y.to(device, non_blocking=True)
        pred, log_err = net(x)
        err = (pred - y.clamp(-0.5, 1.5)).abs()
        # Corners by plain L1; the confidence learns how big the error is.
        loss = err.mean() + 0.2 * (err.detach() * (-log_err).exp() + log_err).mean()
        opt.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(net.parameters(), 5.0)
        opt.step()
        running = 0.98 * running + 0.02 * err.mean().item() if step > start + 1 else err.mean().item()
        if step % 500 == 0 or step == args.steps:
            torch.save({"net": net.state_dict(), "opt": opt.state_dict(), "step": step}, out / "corner.pt")
            say(f"step {step:6d}  {(time.time() - t0) / (step - start):.2f} s/step  train L1 {running * 100:.2f}%  "
                f"validation: {validate(net, vx, vy, vk, device)}")

    net.cpu().eval()  # exported from the processor, the same either way
    torch.onnx.export(Exported(net), (torch.zeros(1, synth.CHANNELS, 128, 128),), str(out / "wall_corners.onnx"),
                      input_names=["room"], output_names=["corners"], opset_version=17, dynamo=False)
    say(f"exported {out / 'wall_corners.onnx'}")


if __name__ == "__main__":
    main()
