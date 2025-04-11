from flask import Flask, render_template, request, jsonify
from flask_cors import CORS
from telegram import Bot
import asyncio
import logging

# Настройка логирования
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    filename='bot.log'
)
logger = logging.getLogger(__name__)

# Инициализация Flask и Telegram
app = Flask(__name__)
CORS(app)  # Включаем CORS для всех маршрутов

TOKEN = "7250815110:AAGGXP1bWMWLxaoCvJSdy8GNxIL8QClQGS8"
CHAT_ID = 1299133852
bot = Bot(token=TOKEN)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/send_message', methods=['POST'])
async def send_message():
    try:
        data = request.json
        message = data.get('message', '')
        
        if not message:
            return jsonify({"status": "error", "message": "Message is required"}), 400

        # Отправляем сообщение в Telegram
        await bot.send_message(chat_id=CHAT_ID, text=message)
        logger.info(f"Сообщение отправлено: {message}")
        
        return jsonify({
            "status": "success",
            "message": "Message sent successfully"
        })
    except Exception as e:
        logger.error(f"Ошибка при отправке сообщения: {e}")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True) 