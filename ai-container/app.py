import json
import boto3
import os
import time
import random
import urllib.parse
from decimal import Decimal

# Clientes AWS (Iniciados fora do handler para performance)
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('DYNAMODB_TABLE')

def handler(event, context):
    print("🔮 [IA Container] Iniciando análise oncológica simulada...")

    # 1. Identificar o arquivo que chegou no S3
    try:
        record = event['Records'][0]
        bucket = record['s3']['bucket']['name']
        # Decodifica o nome do arquivo (remove %20 etc)
        key = urllib.parse.unquote_plus(record['s3']['object']['key'], encoding='utf-8')
        print(f"📂 Arquivo recebido: {key} no bucket {bucket}")

        # Extrair ID do paciente do nome do arquivo (ex: "exames/12345.jpg" -> "12345")
        paciente_id = key.split('/')[-1].split('.')[0]

    except Exception as e:
        print(f"❌ Erro ao ler evento S3: {str(e)}")
        # Retornamos sucesso para o S3 não ficar tentando reenviar o evento infinitamente em caso de erro de parse
        return {"statusCode": 200, "body": "Erro no parse, ignorado"}

    # 2. Simular Processamento Pesado (O "tempo" da IA)
    print("🧠 Carregando modelo TensorFlow (Simulado)...")
    time.sleep(2) # Simula latência de inferência

    # 3. Gerar Diagnóstico
    riscos = ['BAIXO', 'MEDIO', 'ALTO']
    risco_escolhido = random.choice(riscos)

    # Score aleatório baseado no risco
    if risco_escolhido == 'ALTO':
        score = round(random.uniform(0.80, 0.99), 2)
    elif risco_escolhido == 'MEDIO':
        score = round(random.uniform(0.40, 0.79), 2)
    else:
        score = round(random.uniform(0.01, 0.39), 2)

    print(f"✅ Diagnóstico Concluído: Risco {risco_escolhido} (Score: {score})")

    # 4. Atualizar DynamoDB
    if table_name:
        try:
            table = dynamodb.Table(table_name)
            # Atualiza apenas os campos de resultado, mantendo o resto (nome, idade)
            table.update_item(
                Key={'pacienteId': paciente_id},
                UpdateExpression="set #s = :s, #r = :r, #sc = :sc, #data = :dt",
                ExpressionAttributeNames={
                    '#s': 'status',
                    '#r': 'risco',
                    '#sc': 'score',
                    '#data': 'dataAnalise'
                },
                ExpressionAttributeValues={
                    ':s': 'CONCLUIDO',
                    ':r': risco_escolhido,
                    ':sc': Decimal(str(score)),
                    ':dt': str(time.time())
                }
            )
            print("💾 Resultado salvo no DynamoDB com sucesso.")
        except Exception as e:
            print(f"❌ Erro ao salvar no DynamoDB: {str(e)}")
            raise e
    else:
        print("⚠️ Variável DYNAMODB_TABLE não configurada. Pulando salvamento.")

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Analise processada", "id": paciente_id})
    }