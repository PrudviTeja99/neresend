import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 0 = Nearby Tab, 1 = Remote Tab
final activeTabProvider = StateProvider<int>((ref) => 0);

