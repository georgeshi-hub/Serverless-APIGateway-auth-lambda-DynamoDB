import requests
import psutil
from datetime import datetime
import time

API_URL = "https://a776st4py3.execute-api.us-east-1.amazonaws.com/test/DynamoDBManager?QueryString1=queryValue1&StageVar1=stageValue1"

def get_cpu_temperature():
    # This function returns the CPU temperature as a float
    temperature = psutil.sensors_temperatures()
    if 'cpu_thermal' in temperature:
        return temperature['cpu_thermal'][0].current
    elif 'cpu-thermal' in temperature:
        return temperature['cpu-thermal'][0].current
    else:
        return None



def post_temperature_to_api():
    temperature = get_cpu_temperature()
    if temperature is not None:
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        data = {
            "operation": "create",
            "payload": {
                "Item": {
                    "time": timestamp,
                    "cpu temperature": str(temperature)
                }
            }
        }
        headers = {
        'HeaderAuth1': 'headerValue1',
        'Content-Type': 'application/json'
        }

        retries = 3  # Number of retries
        for attempt in range(retries):
            try:
                response = requests.post(API_URL,headers=headers, json=data)
                if response.status_code == 200:
                    print("Temperature posted successfully!")
                    break
            except requests.exceptions.ConnectionError:
                print("Failed to connect. Retrying...")
                time.sleep(10)  # Wait for 10 seconds before retrying
        else:
            print("Failed to post temperature after {} attempts.".format(retries))


def main():
    try:
        while True:
            post_temperature_to_api()
            time.sleep(120)  # Wait for 2 minute before posting temperature again
    except KeyboardInterrupt:
        print("Exiting...")

if __name__ == "__main__":
    main()
