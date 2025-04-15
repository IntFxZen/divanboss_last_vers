import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';



class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static const _serverUrl = 'http://109.73.192.169';
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

    static Future<void> initialize() async {
      if (_isInitialized) {
        print('Notification service already initialized');
        return;
      }
      
      print('Initializing notification service...');
      try {
        // Инициализация SharedPreferences
        _prefs = await SharedPreferences.getInstance();
      _lastMessageId = _prefs?.getInt('lastMessageId');
      print('Last message ID from preferences: $_lastMessageId');
      
      // Загрузка списка уже показанных уведомлений
      _loadShownNotifications();

      const androidSettings = AndroidInitializationSettings('ic_notification');
      const settings = InitializationSettings(android: androidSettings);

      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Important notifications channel',
        importance: Importance.max,
        enableVibration: true,
        enableLights: true,
        showBadge: true,
        playSound: true,
      );

      // Инициализация с обработчиком нажатий на уведомления
      await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          print('Notification clicked: ${response.payload}');
        },
      );
      
      // Создание канала уведомлений
      final androidImplementation = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(channel);
        print('Notification channel created successfully');
        
        // Проверка разрешений
        final permissionStatus = await androidImplementation.getNotificationAppLaunchDetails();
        print('Notification permission status: ${permissionStatus?.didNotificationLaunchApp}');
        
        // Запрос разрешения на отправку уведомлений при первом запуске
        final permissionRequested = _prefs?.getBool(_notificationPermissionKey) ?? false;
        if (!permissionRequested) {
          print('Requesting notification permission...');
          final granted = await androidImplementation.requestNotificationsPermission() ?? false;
          print('Notification permission granted: $granted');
          await _prefs?.setBool(_notificationPermissionKey, true);
          
          // Убираем тестовое уведомление
          // if (granted) {
          //   await _showNotification('Проверка уведомлений', 0);
          //   print('Test notification sent');
          // }
        }
      } else {
        print('Android implementation not available');
      }

      // Инициализация Workmanager
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      print('Workmanager initialized');
      
      // Регистрация периодической задачи
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
      print('Periodic task registered');
      
      _isInitialized = true;
      print('Notification service initialized successfully');
    } catch (e) {
      print('Error initializing notification service: $e');
    }
  }

  // Загрузка списка уже показанных уведомлений из SharedPreferences
  static void _loadShownNotifications() {
    try {
      final notificationsJson = _prefs?.getStringList(_shownNotificationsKey) ?? [];
      _shownNotificationIds = notificationsJson.map((id) => int.tryParse(id) ?? 0).toSet();
      print('Loaded ${_shownNotificationIds.length} shown notification IDs');
    } catch (e) {
      print('Error loading shown notifications: $e');
      _shownNotificationIds = {};
    }
  }

  // Сохранение списка уже показанных уведомлений в SharedPreferences
  static Future<void> _saveShownNotifications() async {
    try {
      final idList = _shownNotificationIds.map((id) => id.toString()).toList();
      await _prefs?.setStringList(_shownNotificationsKey, idList);
      print('Saved ${_shownNotificationIds.length} shown notification IDs');
    } catch (e) {
      print('Error saving shown notifications: $e');
    }
  }

  // Очистка старых уведомлений, чтобы список не рос бесконечно
  static void _cleanupOldNotifications() {
    if (_shownNotificationIds.length > 100) {
      // Оставляем только последние 50 уведомлений
      final sortedIds = _shownNotificationIds.toList()..sort();
      _shownNotificationIds = sortedIds.sublist(sortedIds.length - 50).toSet();
      _saveShownNotifications();
    }
  }

  static Future<void> startPolling() async {
    print('Starting polling...');
    _timer?.cancel();
    _timer = Timer.periodic(_pollingInterval, (_) {
      print('Polling timer triggered');
      _checkNewMessages();
    });
    // Сразу проверяем сообщения при запуске
    _checkNewMessages();
  }

  static Future<void> stopPolling() async {
    print('Stopping polling...');
    _timer?.cancel();
    _timer = null;
    
    // Сохраняем текущее состояние перед переходом в фон
    await _saveShownNotifications();
    if (_lastMessageId != null) {
      await _prefs?.setInt('lastMessageId', _lastMessageId!);
    }
    
    // Регистрируем фоновую задачу
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
  }

  static Future<void> _checkNewMessages() async {
    try {
      print('Checking for new messages...');
      final response = await http.get(Uri.parse('$_serverUrl/last-message'))
          .timeout(Duration(seconds: 10));
      print('Server response status: ${response.statusCode}');
      print('Server response body: ${response.body}');

      if (response.statusCode == 200) {
        final message = json.decode(response.body);
        print('Received message: $message');

        final messageId = message['id'] as int;
        
        // Проверяем перезапуск сервера (если новый ID меньше предыдущего)
        if (_lastMessageId != null && messageId < _lastMessageId!) {
          print('Server restart detected (new ID < last ID). Clearing shown notifications...');
          _shownNotificationIds.clear();
          await _saveShownNotifications();
          _lastMessageId = null;
          await _prefs?.remove('lastMessageId');
        }

        // Проверяем новое сообщение
        if (_lastMessageId == null || messageId != _lastMessageId) {
          print('New message detected. Last ID: $_lastMessageId, New ID: $messageId');
          _lastMessageId = messageId;
          await _prefs?.setInt('lastMessageId', _lastMessageId!);
          
          // Проверяем, не было ли это уведомление уже показано
          if (!_shownNotificationIds.contains(messageId)) {
            print('Message ID $messageId not shown before, showing notification...');
            await _showNotification(message['text'], messageId);
            _shownNotificationIds.add(messageId);
            await _saveShownNotifications();
            _cleanupOldNotifications();
          } else {
            print('Message ID $messageId already shown, skipping...');
          }
        } else {
          print('Message ID $messageId already processed');
        }
      } else if (response.statusCode == 404) {
        print('No messages available on server yet');
      } else {
        print('Server returned error status: ${response.statusCode}');
        print('Response body: ${response.body}');
      }
    } catch (e) {
      print('Error checking messages: $e');
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
    
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      enableLights: true,
      onlyAlertOnce: true,
      autoCancel: true,
      playSound: true,
      icon: 'ic_notification',
      ticker: 'Новое уведомление',
      category: AndroidNotificationCategory.message,
    );

    const details = NotificationDetails(android: androidDetails);

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
  print('Background task started');
  Workmanager().executeTask((_, __) async {
    print('Workmanager task executing');
    try {
      // Инициализируем SharedPreferences для фоновой задачи
      final prefs = await SharedPreferences.getInstance();
      NotificationService._prefs = prefs;
      
      // Загружаем список показанных уведомлений
      NotificationService._loadShownNotifications();
      
      // Загружаем последний ID сообщения
      NotificationService._lastMessageId = prefs.getInt('lastMessageId');
      print('Loaded last message ID in background: ${NotificationService._lastMessageId}');
      
      await NotificationService._checkNewMessages();
      return true;
    } catch (e) {
      print('Error in background task: $e');
      return false;
    }
  });
}
