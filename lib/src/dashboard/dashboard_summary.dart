import 'package:mac_fan_tool/src/dashboard/dashboard_support.dart';
import 'package:mac_fan_tool/src/hardware/hardware_models.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.overallTemperature,
    required this.cpuAverage,
    required this.gpuAverage,
    required this.powerAverage,
    required this.diskAverage,
    required this.memoryAverage,
    required this.ambientAverage,
    required this.sensorCount,
    required this.cpuSensorCount,
    required this.gpuSensorCount,
    required this.powerSensorCount,
    required this.diskSensorCount,
    required this.memorySensorCount,
    required this.ambientSensorCount,
    required this.overallCaption,
  });

  factory DashboardSummary.fromSnapshot(HardwareSnapshotData snapshot) {
    final sensors = snapshot.sensorReadings;
    final cpu = cpuSensors(sensors);
    final gpu = gpuSensors(sensors);
    final power = powerSensors(sensors);
    final disk = diskSensors(sensors);
    final memory = memorySensors(sensors);
    final ambient = ambientSensors(sensors);

    final cpuAverage = mean(cpu.map((sensor) => sensor.numericValue));
    final gpuAverage = mean(gpu.map((sensor) => sensor.numericValue));
    final powerAverage = mean(power.map((sensor) => sensor.numericValue));
    final diskAverage = mean(disk.map((sensor) => sensor.numericValue));
    final memoryAverage = mean(memory.map((sensor) => sensor.numericValue));
    final ambientAverage = mean(ambient.map((sensor) => sensor.numericValue));

    final categoryAverages = [
      cpuAverage,
      gpuAverage,
      powerAverage,
      diskAverage,
      memoryAverage,
      ambientAverage,
    ].whereType<double>().toList();

    final overallTemperature = mean(categoryAverages);
    final fallbackOverall =
        overallTemperature ??
        mean(sensors.map((sensor) => sensor.numericValue));

    return DashboardSummary(
      overallTemperature: fallbackOverall,
      cpuAverage: cpuAverage,
      gpuAverage: gpuAverage,
      powerAverage: powerAverage,
      diskAverage: diskAverage,
      memoryAverage: memoryAverage,
      ambientAverage: ambientAverage,
      sensorCount: sensors.length,
      cpuSensorCount: cpu.length,
      gpuSensorCount: gpu.length,
      powerSensorCount: power.length,
      diskSensorCount: disk.length,
      memorySensorCount: memory.length,
      ambientSensorCount: ambient.length,
      overallCaption: categoryAverages.isEmpty
          ? 'Waiting for enough temperature channels to calculate a balanced system reading.'
          : 'Balanced mean of CPU, GPU, power, disk, memory, and ambient groups when available.',
    );
  }

  final double? overallTemperature;
  final double? cpuAverage;
  final double? gpuAverage;
  final double? powerAverage;
  final double? diskAverage;
  final double? memoryAverage;
  final double? ambientAverage;

  final int sensorCount;
  final int cpuSensorCount;
  final int gpuSensorCount;
  final int powerSensorCount;
  final int diskSensorCount;
  final int memorySensorCount;
  final int ambientSensorCount;
  final String overallCaption;
}

class FanSummary {
  const FanSummary({
    required this.fanCount,
    required this.averageRpm,
    required this.peakRpm,
    required this.manualCount,
  });

  factory FanSummary.fromFans(List<FanReadingData> fans) {
    var totalRpm = 0;
    var peakRpm = 0;
    var manualCount = 0;

    for (final fan in fans) {
      totalRpm += fan.safeCurrentRpm;
      if (fan.safeCurrentRpm > peakRpm) {
        peakRpm = fan.safeCurrentRpm;
      }
      if (fan.normalizedMode == FanModeData.manual) {
        manualCount += 1;
      }
    }

    return FanSummary(
      fanCount: fans.length,
      averageRpm: (totalRpm / fans.length).round(),
      peakRpm: peakRpm,
      manualCount: manualCount,
    );
  }

  final int fanCount;
  final int averageRpm;
  final int peakRpm;
  final int manualCount;
}
