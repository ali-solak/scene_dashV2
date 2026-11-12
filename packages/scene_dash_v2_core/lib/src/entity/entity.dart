extension type const Entity._(int _bits) implements Object {
  static const int _span = 0x1000000;
  static const int indexMask = 0xFFFFFF;
  static const int generationMask = 0x1FFFFFFF;
  static const int maxIndex = indexMask - 1;

  const Entity(int index, int generation)
    : _bits = (generation & generationMask) * _span + index;

  static const Entity invalid = Entity._(indexMask);

  int get index => _bits & indexMask;

  int get generation => _bits ~/ _span;

  bool get isValid => index != indexMask;

  String get label => 'Entity($index v$generation)';
}
