from flask import Flask, request, jsonify
import requests
import os
import sys
import json



app = Flask(__name__)

# get target URL from environment variable
target_url = os.getenv('TARGET_URL', 'http://172.17.0.4:8000/scan/prompt')

# output target URL to stderr
print(f"Target URL: {target_url}", file=sys.stderr)

# handle multiple routes
@app.route('/scan/prompt', methods=['POST'])
@app.route('/', methods=['POST', 'GET'])
@app.route('/<path:path>', methods=['POST', 'GET'])


def proxy(path = None):
    # Read the JSON data from the incoming request
    if request.is_json:
        data = request.get_json()
    else:
        try:
            print(f"request.data: {request.data}", file=sys.stderr)
            data = json.loads(request.data)
        except ValueError:
            return jsonify({"error": "Invalid JSON"}), 400
    if not data or 'messages' not in data:
        return jsonify({'error': 'Invalid JSON or missing key'}), 400

    messages = data['messages']

    prompts = " ".join([message["content"] for message in messages if message["role"] != "user123123123"])

    print(f"prompt: {prompts}", file=sys.stderr)

    # Modify the data as needed
    modified_data = {
        "prompt": prompts,
        "scanners_suppress": ["BanSubstrings", "Sentiment"]
    }

    # Forward the modified request to another service
    response = requests.post(target_url, json=modified_data)

    # parse json response
    response_json = response.json()
    # get is_valid key status
    is_valid = response_json.get('is_valid', False)

    # if is_valid is False, return the response to the client with status code 400
    status_code = 200 if is_valid else 405

    # Return the response from the proxied request to the client
    return (response.content, status_code, response.headers.items())

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
