import 'package:flutter/services.dart';

class ForegroundSync {
  static const _channel = MethodChannel('steam_achievements/sync');

  Future<bool> areNotificationsAllowed() async {
    return await _channel.invokeMethod<bool>('areNotificationsAllowed') ?? true;
  }

  Future<bool> requestNotifications() async {
    return await _channel.invokeMethod<bool>('requestNotifications') ?? true;
  }

  Future<void> start() async {
    await _channel.invokeMethod<void>('startForegroundSync');
  }
}
