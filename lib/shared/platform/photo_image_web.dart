import 'package:flutter/material.dart';

import 'photo_error.dart';

Widget photoImage(
  String path, {
  BoxFit fit = BoxFit.contain,
  double? width,
  double? height,
}) =>
    Image.network(
      path,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => const PhotoError(),
    );

/// The same photo as an [ImageProvider], for screens that need its size or
/// draw it themselves (one decode, shared through the image cache).
ImageProvider photoProvider(String path) => NetworkImage(path);
