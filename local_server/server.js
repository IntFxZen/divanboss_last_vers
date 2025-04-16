const express = require('express');
const TelegramBot = require('node-telegram-bot-api');
const cors = require('cors');

const app = express();
const port = 3000;

let bot = null;

// Хранение данных
let lastMessage = null;
let userStates = {};
let messageCounter = 0;
let isReconnecting = false;

// Функция создания и инициализации бота
function initBot() {
    try {
        bot = new TelegramBot('7250815110:AAGGXP1bWMWLxaoCvJSdy8GNxIL8QClQGS8', { 
            polling: true,
            testEnvironment: false,
            timeout: 30
        });

        // Обработка ошибок бота
        bot.on('polling_error', async (error) => {
            console.error('Ошибка polling:', error.code, error.message);
            if (!isReconnecting) {
                await reconnectBot();
            }
        });

        bot.on('error', async (error) => {
            console.error('Общая ошибка бота:', error.code, error.message);
            if (!isReconnecting) {
                await reconnectBot();
            }
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

        console.log('Бот успешно инициализирован');
        return true;
    } catch (error) {
        console.error('Ошибка при инициализации бота:', error);
        return false;
    }
}

// Функция переподключения бота
async function reconnectBot() {
    if (isReconnecting) return;
    
    isReconnecting = true;
    console.log('Начало процесса переподключения бота...');
    
    try {
        if (bot) {
            try {
                await bot.stopPolling();
            } catch (e) {
                console.error('Ошибка при остановке бота:', e);
            }
        }

        // Ждем некоторое время перед переподключением
        await new Promise(resolve => setTimeout(resolve, 5000));

        let reconnected = false;
        let attempts = 0;
        const maxAttempts = 5;

        while (!reconnected && attempts < maxAttempts) {
            attempts++;
            console.log(`Попытка переподключения ${attempts}/${maxAttempts}...`);
            
            reconnected = initBot();
            
            if (!reconnected) {
                await new Promise(resolve => setTimeout(resolve, 5000));
            }
        }

        if (reconnected) {
            console.log('Бот успешно переподключен');
        } else {
            console.error('Не удалось переподключить бота после', maxAttempts, 'попыток');
        }
    } catch (error) {
        console.error('Ошибка при попытке переподключения:', error);
    } finally {
        isReconnecting = false;
    }
}

// Middleware
app.use(cors());
app.use(express.json());

const ALLOWED_USER_ID = 1299133852;

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

// Запуск сервера и инициализация бота
app.listen(port, () => {
    console.log(`Сервер запущен на порту ${port}`);
    initBot();
});

// Периодическая проверка состояния бота
setInterval(async () => {
    if (bot && !isReconnecting) {
        try {
            await bot.getMe();
        } catch (error) {
            console.error('Ошибка при проверке состояния бота:', error);
            await reconnectBot();
        }
    }
}, 60000); // Проверка каждую минуту 