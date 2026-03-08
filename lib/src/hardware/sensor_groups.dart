import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

List<SensorReadingData> cpuSensors(List<SensorReadingData> sensors) {
  return _sortedSensors([
    for (final sensor in sensors)
      if (sensor.normalizedKind == SensorKindData.cpu) sensor,
  ]);
}

List<SensorReadingData> gpuSensors(List<SensorReadingData> sensors) {
  return _sortedSensors([
    for (final sensor in sensors)
      if (sensor.normalizedKind == SensorKindData.gpu) sensor,
  ]);
}

List<SensorReadingData> memorySensors(List<SensorReadingData> sensors) {
  return _sortedSensors([
    for (final sensor in sensors)
      if (sensor.normalizedKind == SensorKindData.memory) sensor,
  ]);
}

List<SensorReadingData> ambientSensors(List<SensorReadingData> sensors) {
  return _sortedSensors([
    for (final sensor in sensors)
      if (sensor.normalizedKind == SensorKindData.ambient) sensor,
  ]);
}

List<SensorReadingData> diskSensors(List<SensorReadingData> sensors) {
  return _sortedSensors([
    for (final sensor in sensors)
      if (matchesSensorCategory(sensor, const ['ssd', 'nand', 'disk'])) sensor,
  ]);
}

List<SensorReadingData> powerSensors(List<SensorReadingData> sensors) {
  return _sortedSensors([
    for (final sensor in sensors)
      if (sensor.normalizedKind == SensorKindData.other &&
          matchesSensorCategory(sensor, const [
            'power',
            'supply',
            'pmgr',
            'manager',
            'pmu',
            'calibration',
          ]))
        sensor,
  ]);
}

List<SensorReadingData> supportingSensors(List<SensorReadingData> sensors) {
  final cpuIds = cpuSensors(sensors).map((sensor) => sensor.stableId).toSet();
  final gpuIds = gpuSensors(sensors).map((sensor) => sensor.stableId).toSet();

  return _sortedSensors([
    for (final sensor in sensors)
      if (!cpuIds.contains(sensor.stableId) &&
          !gpuIds.contains(sensor.stableId))
        sensor,
  ]);
}

double? mean(Iterable<double> values) {
  final finiteValues = values.where((value) => value.isFinite).toList();
  if (finiteValues.isEmpty) {
    return null;
  }
  return finiteValues.reduce((left, right) => left + right) /
      finiteValues.length;
}

bool matchesSensorCategory(SensorReadingData sensor, List<String> keywords) {
  final text = '${sensor.displayName} ${sensor.stableId}'.toLowerCase();
  for (final keyword in keywords) {
    if (text.contains(keyword)) {
      return true;
    }
  }
  return false;
}

List<SensorReadingData> _sortedSensors(Iterable<SensorReadingData> sensors) {
  final sorted = sensors.toList();
  sorted.sort((left, right) {
    final byName = _naturalCompare(left.displayName, right.displayName);
    if (byName != 0) {
      return byName;
    }
    return _naturalCompare(left.stableId, right.stableId);
  });
  return sorted;
}

int _naturalCompare(String left, String right) {
  final leftText = left.toLowerCase();
  final rightText = right.toLowerCase();
  var leftIndex = 0;
  var rightIndex = 0;

  while (leftIndex < leftText.length && rightIndex < rightText.length) {
    final leftCode = leftText.codeUnitAt(leftIndex);
    final rightCode = rightText.codeUnitAt(rightIndex);
    final leftIsDigit = _isDigit(leftCode);
    final rightIsDigit = _isDigit(rightCode);

    if (leftIsDigit && rightIsDigit) {
      final leftStart = leftIndex;
      final rightStart = rightIndex;

      while (leftIndex < leftText.length &&
          _isDigit(leftText.codeUnitAt(leftIndex))) {
        leftIndex++;
      }
      while (rightIndex < rightText.length &&
          _isDigit(rightText.codeUnitAt(rightIndex))) {
        rightIndex++;
      }

      final leftNumber = int.parse(leftText.substring(leftStart, leftIndex));
      final rightNumber = int.parse(
        rightText.substring(rightStart, rightIndex),
      );
      final comparison = leftNumber.compareTo(rightNumber);
      if (comparison != 0) {
        return comparison;
      }
      continue;
    }

    if (leftCode != rightCode) {
      return leftCode.compareTo(rightCode);
    }

    leftIndex++;
    rightIndex++;
  }

  return leftText.length.compareTo(rightText.length);
}

bool _isDigit(int codeUnit) {
  return codeUnit >= 48 && codeUnit <= 57;
}
