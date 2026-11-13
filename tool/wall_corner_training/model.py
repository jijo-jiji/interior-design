"""The wall-corner model: depth and labels in, the front wall's corners out."""

import torch
from torch import nn

import synth

OUTPUTS = 2 * synth.POINTS  # x and y of each point

# Where corners usually are, so training starts from a sensible wall: the
# four corners, then the two hidden bottom corners.
_START = [0.15, 0.15, 0.85, 0.15, 0.85, 0.85, 0.15, 0.85, 0.85, 0.85, 0.15, 0.85]


class CornerNet(nn.Module):
    """A small CNN over the 128 × 128 input.

    Outputs 2 × OUTPUTS numbers: the points as fractions of the photo (see
    synth.sample: the corners as marked, then the hidden bottom corners), then,
    for each coordinate, how far off the model expects to be (log scale): its
    own confidence.
    """

    def __init__(self, channels: int = synth.CHANNELS):
        super().__init__()

        def block(i, o, stride):
            return nn.Sequential(nn.Conv2d(i, o, 3, stride, 1, bias=False), nn.BatchNorm2d(o), nn.ReLU(inplace=True))

        self.features = nn.Sequential(
            block(channels, 32, 2), block(32, 32, 1),  # 64
            block(32, 64, 2), block(64, 64, 1),  # 32
            block(64, 96, 2), block(96, 96, 1),  # 16
            block(96, 160, 2), block(160, 160, 1),  # 8
            block(160, 224, 2),  # 4
        )
        self.head = nn.Sequential(nn.Flatten(), nn.Linear(224 * 16, 256), nn.ReLU(inplace=True),
                                  nn.Linear(256, 2 * OUTPUTS))
        with torch.no_grad():
            self.head[-1].bias[:OUTPUTS] = torch.tensor(_START)
            self.head[-1].bias[OUTPUTS:] = -3.0  # expect about 5% off to begin with

    def forward(self, x):
        out = self.head(self.features(x))
        return out[:, :OUTPUTS], out[:, OUTPUTS:]


# A model trained before the hidden bottom corners were added (16 outputs:
# 4 corners, then their 8 confidences) starts a new one: those corners were
# the true ones, so they seed both the corners as marked and the hidden ones.
_FROM_FOUR = [0, 1, 2, 3, 4, 5, 6, 7, 4, 5, 6, 7]


def init_from(net: CornerNet, state: dict) -> None:
    """Loads [state] (a CornerNet state dict) into [net], carrying an older
    4-corner model's last layer over to the 6-point one."""
    own = net.state_dict()
    last_w, last_b = "head.3.weight", "head.3.bias"
    if state[last_b].shape[0] == 16 and own[last_b].shape[0] == 2 * OUTPUTS:
        rows = _FROM_FOUR + [8 + i for i in _FROM_FOUR]
        state = dict(state)
        state[last_w] = state[last_w][rows]
        state[last_b] = state[last_b][rows]
    net.load_state_dict(state)


class Exported(nn.Module):
    """For the app: one output, the points then their expected errors (not log)."""

    def __init__(self, net: CornerNet):
        super().__init__()
        self.net = net

    def forward(self, x):
        corners, log_err = self.net(x)
        return torch.cat([corners, log_err.exp()], 1)
