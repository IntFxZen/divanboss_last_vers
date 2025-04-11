const express = require('express');
const TelegramBot = require('node-telegram-bot-api');
const cors = require('cors');

const app = express();
const port = 3000;

// Инициализация бота
const bot = new TelegramBot('7250815110:AAGGXP1bWMWLxaoCvJSdy8GNxIL8QClQGS8', { polling: true });
const ALLOWED_USER_ID = 1299133852;

// Хранение данных
let lastMessage = null;
let userStates = {};
let messageCounter = 0;

// Middleware
app.use(cors());
app.use(express.json());

// Обработка ошибок бота
bot.on('polling_error', (error) => {
    console.error('Ошибка polling:', error);
});

// Обработка команды /start
bot.onText(/\/start/, (msg) => {
    console.log('Получена команда /start от:', msg.from.id);
    const chatId = msg.chat.id;
    if (msg.from.id === ALLOWED_USER_ID) {
        const keyboard = {
            reply_markup: {
                keyboard: [
                    [{ text: 'Создать уведомление' }]
                ],
                resize_keyboard: true
            }
        };
        bot.sendMessage(chatId, 'Выберите действие:', keyboard)
            .then(() => console.log('Сообщение start отправлено успешно'))
            .catch(error => console.error('Ошибка отправки start сообщения:', error));
    } else {
        console.log('Попытка неавторизованного доступа от:', msg.from.id);
    }
});

// Обработка нажатия кнопки "Создать уведомление"
bot.onText(/Создать уведомление/, (msg) => {
    console.log('Получено нажатие кнопки "Создать уведомление" от:', msg.from.id);
    const chatId = msg.chat.id;
    if (msg.from.id === ALLOWED_USER_ID) {
        userStates[chatId] = { step: 'waiting_for_title' };
        bot.sendMessage(chatId, 'Введите заголовок уведомления:')
            .then(() => console.log('Запрос заголовка отправлен успешно'))
            .catch(error => console.error('Ошибка отправки запроса заголовка:', error));
    }
});

// Обработка сообщений от бота
bot.on('message', (msg) => {
    console.log('Получено сообщение:', msg.text, 'от:', msg.from.id);
    const chatId = msg.chat.id;
    
    if (msg.from.id !== ALLOWED_USER_ID) {
        console.log('Попытка неавторизованного доступа от:', msg.from.id);
        bot.sendMessage(chatId, 'Извините, у вас нет доступа к этому боту.')
            .catch(error => console.error('Ошибка отправки сообщения о неавторизованном доступе:', error));
        return;
    }

    if (msg.text && !msg.text.startsWith('/') && msg.text !== 'Создать уведомление') {
        const userState = userStates[chatId];
        if (userState) {
            if (userState.step === 'waiting_for_title') {
                userState.title = msg.text;
                userState.step = 'waiting_for_text';
                console.log('Получен заголовок:', msg.text);
                bot.sendMessage(chatId, 'Введите текст уведомления:')
                    .then(() => console.log('Запрос текста отправлен успешно'))
                    .catch(error => console.error('Ошибка отправки запроса текста:', error));
            } else if (userState.step === 'waiting_for_text') {
                messageCounter = (messageCounter + 1) % 2147483647;
                const notification = {
                    id: messageCounter,
                    text: `${userState.title}: ${msg.text}`
                };
                console.log('Создано новое уведомление:', notification);
                lastMessage = notification;
                delete userStates[chatId];
                bot.sendMessage(chatId, 'Уведомление создано и будет отправлено на устройство!')
                    .then(() => console.log('Сообщение об успехе отправлено'))
                    .catch(error => console.error('Ошибка отправки сообщения об успехе:', error));
            }
        }
    }
});

// API endpoint для получения последнего сообщения
app.get('/last-message', (req, res) => {
    console.log('Получен GET запрос /last-message');
    if (lastMessage) {
        console.log('Отправка последнего сообщения:', lastMessage);
        res.json(lastMessage);
    } else {
        console.log('Нет доступных сообщений');
        res.status(404).json({ error: 'Нет доступных сообщений' });
    }
});

// Запуск сервера
app.listen(port, () => {
    console.log(`Сервер запущен на порту ${port}`);
}); 