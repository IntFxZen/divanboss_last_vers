import os
import time
import logging
from telegram import Bot
from telegram.ext import Updater, MessageHandler, Filters, CommandHandler

# Настройка логирования
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    filename='bot.log'
)
logger = logging.getLogger(__name__)

# Инициализация бота
TOKEN = "7250815110:AAGGXP1bWMWLxaoCvJSdy8GNxIL8QClQGS8"
CHAT_ID = 1299133852

def start(update, context):
    """Обработчик команды /start"""
    update.message.reply_text('Привет! Я бот для уведомлений.')

def handle_message(update, context):
    """Обработчик текстовых сообщений"""
    try:
        message = update.message.text
        logger.info(f"Получено сообщение: {message}")
        
        # Отправляем подтверждение
        update.message.reply_text(f"✅ Сообщение получено: {message}")
        
    except Exception as e:
        logger.error(f"Ошибка при обработке сообщения: {e}")

def error_handler(update, context):
    """Обработчик ошибок"""
    logger.error(f"Ошибка в боте: {context.error}")

def main():
    try:
        # Создаем updater
        updater = Updater(TOKEN, use_context=True)
        dp = updater.dispatcher
        
        # Регистрируем обработчики
        dp.add_handler(CommandHandler("start", start))
        dp.add_handler(MessageHandler(Filters.text, handle_message))
        dp.add_error_handler(error_handler)
        
        # Запускаем бота
        logger.info("Бот запущен...")
        updater.start_polling()
        
        # Держим бота запущенным
        updater.idle()
        
    except Exception as e:
        logger.error(f"Критическая ошибка: {e}")
        time.sleep(60)  # Ждем минуту перед перезапуском
        main()  # Перезапускаем бота

if __name__ == '__main__':
    main() 