from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from telegram import Bot
import logging
from urllib.parse import parse_qs, urlparse
import ssl

# Настройка логирования
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    filename='bot.log'
)
logger = logging.getLogger(__name__)

# Инициализация Telegram бота
TOKEN = "7250815110:AAGGXP1bWMWLxaoCvJSdy8GNxIL8QClQGS8"
CHAT_ID = 1299133852
bot = Bot(token=TOKEN)

class RequestHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_POST(self):
        if self.path == '/api/send_message':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            message = data.get('message', '')
            if not message:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({
                    "status": "error",
                    "message": "Message is required"
                }).encode())
                return

            try:
                # Отправляем сообщение в Telegram
                bot.send_message(chat_id=CHAT_ID, text=message)
                logger.info(f"Сообщение отправлено: {message}")
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({
                    "status": "success",
                    "message": "Message sent successfully"
                }).encode())
            except Exception as e:
                logger.error(f"Ошибка при отправке сообщения: {e}")
                self.send_response(500)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({
                    "status": "error",
                    "message": str(e)
                }).encode())
        else:
            self.send_response(404)
            self.end_headers()

def run(server_class=HTTPServer, handler_class=RequestHandler, port=5000):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f"Сервер запущен на порту {port}")
    httpd.serve_forever()

if __name__ == '__main__':
    run() 