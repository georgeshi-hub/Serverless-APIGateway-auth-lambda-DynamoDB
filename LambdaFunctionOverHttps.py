import boto3
import json
import os
import logging
from botocore.exceptions import ClientError

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

# Retrieve the DynamoDB table name from Terraform environment variable
tableName = os.environ['TABLE_NAME']
logger.info(f"Table name: {tableName}")

# Create the DynamoDB resource
dynamo = boto3.resource('dynamodb').Table(tableName)

def lambda_handler(event, context):
    '''Provide an event that contains the following keys:
      - operation: one of the operations in the operations dict below
      - payload: a JSON object containing parameters to pass to the 
                 operation being performed
    '''
    logger.info(f"Received event: {json.dumps(event)}")
    
    body_string = event.get('body', '{}')
    logger.info(f"Body string: {body_string}")
    
    try:
        body_json = json.loads(body_string)
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return {
            'statusCode': 400,
            'body': json.dumps({'message': 'Invalid JSON format in body'})
        }
    
    operation = body_json.get('operation')
    logger.info(f"Operation: {operation}")
    
    def ddb_create(x):
        try:
            dynamo.put_item(Item=x['Item'])
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Item created successfully'})
            }
        except ClientError as e:
            logger.error(f"Error creating item: {e}")
            return {
                'statusCode': 500,  # Internal Server Error
                'body': json.dumps({'message': f'Error creating item: {e}'})
            }
    
    def ddb_read(x):
        try:
            response = dynamo.get_item(Key=x['Key'])
            return {
                'statusCode': 200,
                'body': json.dumps(response)
            }
        except ClientError as e:
            logger.error(f"Error reading item: {e}")
            return {
                'statusCode': 500,
                'body': json.dumps({'message': f'Error reading item: {e}'})
            }
    
    def ddb_update(x):
        if 'Key' not in x:
            logger.error("Missing 'Key' in payload for update operation")
            return {
                'statusCode': 400,
                'body': json.dumps({'message': "Missing 'Key' in payload for update operation"})
            }
        try:
            dynamo.update_item(
                Key=x['Key'],
                UpdateExpression=x['UpdateExpression'],
                ExpressionAttributeNames=x.get('ExpressionAttributeNames', {}),
                ExpressionAttributeValues=x.get('ExpressionAttributeValues', {})
            )
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Item updated successfully'})
            }
        except ClientError as e:
            logger.error(f"Error updating item: {e}")
            return {
                'statusCode': 500,  # Internal Server Error
                'body': json.dumps({'message': f'Error updating item: {e}'})
            }
    
    def ddb_delete(x):
        if 'Key' not in x:
            logger.error("Missing 'Key' in payload for delete operation")
            return {
                'statusCode': 400,
                'body': json.dumps({'message': "Missing 'Key' in payload for delete operation"})
            }
        try:
            dynamo.delete_item(Key=x['Key'])
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Item deleted successfully'})
            }
        except ClientError as e:
            logger.error(f"Error deleting item: {e}")
            return {
                'statusCode': 500,  # Internal Server Error
                'body': json.dumps({'message': f'Error deleting item: {e}'})
            }
    
    def echo(x):
        return {
            'statusCode': 200,
            'body': json.dumps(x)
        }
    
    operations = {
        'create': ddb_create,
        'read': ddb_read,
        'update': ddb_update,
        'delete': ddb_delete,
        'echo': echo,
    }
    
    if operation in operations:
        payload = body_json.get('payload', {})
        logger.info(f"Payload: {json.dumps(payload)}")
        response = operations[operation](payload)
        return response
    else:
        logger.error(f"Unrecognized operation: {operation}")
        return {
            'statusCode': 400,
            'body': json.dumps({'message': f'Unrecognized operation "{operation}"'})
        }
