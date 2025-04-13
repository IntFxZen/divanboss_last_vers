import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static const _serverUrl = 'http://192.168.0.14:3000';
  static Timer? _timer;
  static int? _lastMessageId;
  static const _pollingInterval = Duration(seconds: 2);
  static const _backgroundInterval = Duration(minutes: 15);
  static const _channelId = 'high_importance_channel';
  static const _channelName = 'High Importance Notifications';
  static SharedPreferences? _prefs;
  static const _notificationPermissionKey = 'notification_permission_requested';
  static bool _isInitialized = false;
  static const _shownNotificationsKey = 'shown_notifications';
  static Set<int> _shownNotificationIds = {};
  static bool _isInForeground = false;

  static Future<void> initialize() async {
    if (_isInitialized) {
      print('Notification service already initialized');
      return;
    }
    
    print('Initializing notification service...');
    try {
      _prefs = await SharedPreferences.getInstance();
      _lastMessageId = _prefs?.getInt('lastMessageId');
      print('Last message ID from preferences: $_lastMessageId');
      
      await _loadShownNotifications();

      const androidSettings = AndroidInitializationSettings('ic_notification');
      const settings = InitializationSettings(android: androidSettings);

      final channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Important notifications channel',
        importance: Importance.max,
        enableVibration: true,
        enableLights: true,
        showBadge: true,
        playSound: true,
      );

      await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          print('Notification clicked: ${response.payload}');
        },
      );
      
      final androidImplementation = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        await androidImplementation.createNotificationChannel(channel);
        print('Notification channel created successfully');
        
        // Отправляем тестовое уведомление
        await _showNotification('Тестовое уведомление', DateTime.now().millisecondsSinceEpoch);
      }

      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      
      await Workmanager().registerPeriodicTask(
        "notificationTask",
        "notificationTask",
        frequency: _backgroundInterval,
        initialDelay: Duration.zero,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
      
      _isInitialized = true;
      print('Notification service initialized successfully');
    } catch (e) {
      print('Error initializing notification service: $e');
    }
  }

  static Future<void> _loadShownNotifications() async {
    try {
      final notificationsJson = _prefs?.getStringList(_shownNotificationsKey) ?? [];
      _shownNotificationIds = notificationsJson.map((id) => int.parse(id)).toSet();
      print('Loaded ${_shownNotificationIds.length} shown notification IDs');
    } catch (e) {
      print('Error loading shown notifications: $e');
      _shownNotificationIds = {};
    }
  }

  static Future<void> _saveShownNotifications() async {
    try {
      final idList = _shownNotificationIds.map((id) => id.toString()).toList();
      await _prefs?.setStringList(_shownNotificationsKey, idList);
      print('Saved ${_shownNotificationIds.length} shown notification IDs');
    } catch (e) {
      print('Error saving shown notifications: $e');
    }
  }

  static Future<void> _cleanupOldNotifications() async {
    if (_shownNotificationIds.length > 100) {
      final sortedIds = _shownNotificationIds.toList()..sort();
      _shownNotificationIds = sortedIds.sublist(sortedIds.length - 50).toSet();
      await _saveShownNotifications();
      print('Cleaned up old notifications, remaining: ${_shownNotificationIds.length}');
    }
  }

  static Future<void> startPolling() async {
    print('Starting foreground polling...');
    _isInForeground = true;
    
    // Отменяем фоновые задачи при запуске переднего плана
    await Workmanager().cancelAll();
    
    _timer?.cancel();
    _timer = Timer.periodic(_pollingInterval, (_) {
      _checkNewMessages();
    });
    // Сразу проверяем сообщения при запуске
    await _checkNewMessages();
  }

  static Future<void> stopPolling() async {
    print('Stopping foreground polling, switching to background...');
    _isInForeground = false;
    _timer?.cancel();
    _timer = null;
    
    // Регистрируем фоновую задачу только при остановке переднего плана
    await Workmanager().registerPeriodicTask(
      "notificationTask",
      "notificationTask",
      frequency: _backgroundInterval,
      initialDelay: Duration.zero,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> _checkNewMessages() async {
    if (!_isInitialized) {
      print('Notification service not initialized, skipping check');
      return;
    }

    try {
      print('Checking for new messages (${_isInForeground ? 'foreground' : 'background'})...');
      final response = await http.get(
        Uri.parse('$_serverUrl/last-message'),
        headers: {'Connection': 'keep-alive'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('Server response: ${response.body}');
        
        if (response.body.isEmpty) {
          print('Empty response from server');
          return;
        }

        try {
          final message = json.decode(response.body);
          if (message != null && message['id'] != null) {
            final messageId = message['id'];
            
            // Проверяем, не перезапустился ли сервер (новый ID меньше предыдущего)
            if (_lastMessageId != null && messageId < _lastMessageId!) {
              print('Server seems to be restarted (ID reset detected). Clearing shown notifications.');
              _shownNotificationIds.clear();
              await _saveShownNotifications();
              _lastMessageId = null;
              await _prefs?.remove('lastMessageId');
            }
            
            // Загружаем актуальный список показанных уведомлений
            await _loadShownNotifications();
            
            print('Checking message ID: $messageId');
            print('Last message ID: $_lastMessageId');
            print('Shown notifications: $_shownNotificationIds');
            
            // Проверяем, не показывали ли мы уже это уведомление
            if (!_shownNotificationIds.contains(messageId)) {
              print('New message detected, ID: $messageId');
              
              // Добавляем ID в список показанных до отправки уведомления
              _shownNotificationIds.add(messageId);
              await _saveShownNotifications();
              
              // Обновляем lastMessageId только для новых сообщений
              if (_lastMessageId == null || messageId > _lastMessageId!) {
                _lastMessageId = messageId;
                await _prefs?.setInt('lastMessageId', _lastMessageId!);
                
                // Показываем уведомление только для новых сообщений
                print('Showing notification for message: ${message['text']}');
                await _showNotification(message['text'] ?? 'Новое сообщение', messageId);
                
                // Очищаем старые уведомления после успешного показа
                await _cleanupOldNotifications();
              } else {
                print('Message ID is older than last shown message');
              }
            } else {
              print('Message already shown, skipping. ID: $messageId');
            }
          } else {
            print('Invalid message format from server');
          }
        } catch (e) {
          print('Error parsing server response: $e');
        }
      } else {
        print('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('Connection error: $e');
    }
  }

  static Future<void> _showNotification(String body, int id) async {
    print('Preparing to show notification...');
    
    String title = 'Новое сообщение';
    String notificationBody = body;
    
    if (body.contains(':')) {
      final parts = body.split(':');
      if (parts.length >= 2) {
        title = parts[0].trim();
        notificationBody = parts.sublist(1).join(':').trim();
      }
    }
    
    print('Notification title: $title');
    print('Notification body: $notificationBody');
    
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Important notifications channel',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      enableLights: true,
      icon: 'ic_notification',
      playSound: true,
      autoCancel: true,
      channelShowBadge: true,
      fullScreenIntent: true,
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      await _notifications.show(
        id,
        title,
        notificationBody,
        details,
        payload: 'notification_clicked',
      );
      print('Notification shown successfully');
    } catch (e) {
      print('Error showing notification: $e');
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('Background task started');
    try {
      // Инициализируем SharedPreferences для фонового режима
      final prefs = await SharedPreferences.getInstance();
      final lastMessageId = prefs.getInt('lastMessageId');
      final shownNotificationsJson = prefs.getStringList('shown_notifications') ?? [];
      final shownNotificationIds = shownNotificationsJson.map((id) => int.parse(id)).toSet();
      
      print('Background task - Last message ID: $lastMessageId');
      print('Background task - Shown notifications count: ${shownNotificationIds.length}');

      // Проверяем новые сообщения
      try {
        final response = await http.get(
          Uri.parse('${NotificationService._serverUrl}/last-message'),
          headers: {'Connection': 'keep-alive'},
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 && response.body.isNotEmpty) {
          final message = json.decode(response.body);
          if (message != null && message['id'] != null) {
            final messageId = message['id'];
            
            // Проверяем, не перезапустился ли сервер (новый ID меньше предыдущего)
            if (lastMessageId != null && messageId < lastMessageId) {
              print('Background task - Server seems to be restarted (ID reset detected). Clearing shown notifications.');
              shownNotificationIds.clear();
              await prefs.setStringList('shown_notifications', []);
              await prefs.remove('lastMessageId');
            }
            
            print('Background task - Received message ID: $messageId');
            
            // Проверяем, не показывали ли мы уже это уведомление
            if (!shownNotificationIds.contains(messageId)) {
              // Проверяем, что сообщение новее последнего показанного
              if (lastMessageId == null || messageId > lastMessageId) {
                print('Background task - Showing new notification');
                
                // Показываем уведомление
                final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
                
                const androidSettings = AndroidInitializationSettings('ic_notification');
                const settings = InitializationSettings(android: androidSettings);
                await notifications.initialize(settings);
                
                String title = 'Новое сообщение';
                String notificationBody = message['text'] ?? '';
                
                if (notificationBody.contains(':')) {
                  final parts = notificationBody.split(':');
                  if (parts.length >= 2) {
                    title = parts[0].trim();
                    notificationBody = parts.sublist(1).join(':').trim();
                  }
                }

                final androidDetails = AndroidNotificationDetails(
                  NotificationService._channelId,
                  NotificationService._channelName,
                  channelDescription: 'Important notifications channel',
                  importance: Importance.max,
                  priority: Priority.high,
                  showWhen: true,
                  enableVibration: true,
                  enableLights: true,
                  icon: 'ic_notification',
                  playSound: true,
                  autoCancel: true,
                  channelShowBadge: true,
                );

                final details = NotificationDetails(android: androidDetails);
                await notifications.show(
                  messageId,
                  title,
                  notificationBody,
                  details,
                );

                // Сохраняем информацию о показанном уведомлении
                shownNotificationIds.add(messageId);
                await prefs.setStringList(
                  'shown_notifications',
                  shownNotificationIds.map((id) => id.toString()).toList(),
                );
                await prefs.setInt('lastMessageId', messageId);
                
                print('Background task - Notification shown and state saved');
              } else {
                print('Background task - Message is older than last shown');
              }
            } else {
              print('Background task - Message already shown');
            }
          }
        }
      } catch (e) {
        print('Background task - Error: $e');
      }
      
      return true;
    } catch (e) {
      print('Background task - Critical error: $e');
      return false;
    }
  });
}
