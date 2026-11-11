import os
from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def index():
    return jsonify({
        "message": "Hello from Flask App!",
        "status": "running",
    })


@app.route("/health")
def health():
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    # ❌ BAD: debug=True aktif di container (berisiko RCE lewat Werkzeug debugger)
    app.run(host="0.0.0.0", port=port, debug=True)
