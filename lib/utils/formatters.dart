class Formatters {
  static String distance(int m) {
    return m >= 1000 ? "${(m / 1000).toStringAsFixed(1)} كم" : "$m م";
  }

  static String duration(int s) {
    if (s < 60) return "$s ث";
    final m = s ~/ 60;
    final rem = s % 60;
    if (m < 60) return rem == 0 ? "$m د" : "$m د ${rem}ث";
    final h = m ~/ 60;
    final mm = m % 60;
    return mm == 0 ? "$h س" : "$h س ${mm}د";
  }
}
