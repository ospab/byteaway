/// App-wide constants for timing and configuration.
class AppDurations {
  AppDurations._();

  static const balanceRefreshSeconds = 60;
  static const balanceCountdownSeconds = 1;
  static const statsRefreshSeconds = 45;
  static const wsReconnectDelaySeconds = 5;
  static const heartbeatIntervalSeconds = 30;
  static const connectionTimeoutSeconds = 10;
}

class AppLimits {
  AppLimits._();

  static const defaultSpeedLimitMbps = 50;
  static const maxSpeedLimitMbps = 100;
  static const minSpeedLimitMbps = 1;
  static const apiMaxRetries = 3;
  static const apiInitialRetryDelayMs = 500;
}
