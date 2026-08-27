/// Light channels: which lights reach which meshes.
library;

import 'package:flutter_scene/scene.dart' show Node;

const int worldLightChannel = 0x01;

const int lockOnLightChannel = 0x02;

const int defaultLightChannels = 0xFF & ~lockOnLightChannel;

void setLightChannels(Node node, int mask) {
  node.lightChannelMask = mask;
  for (final child in node.children) {
    setLightChannels(child, mask);
  }
}
