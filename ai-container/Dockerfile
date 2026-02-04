# Usa a imagem base oficial da AWS para Lambda Python 3.11
FROM public.ecr.aws/lambda/python:3.11

# 1. Copia o arquivo de requisitos
COPY requirements.txt ${LAMBDA_TASK_ROOT}

# 2. Instala as dependências (Boto3) na pasta da Lambda
RUN pip install -r requirements.txt

# 3. Copia o código da função
COPY app.py ${LAMBDA_TASK_ROOT}

# 4. Define quem deve ser chamado (Arquivo.Funcao)
CMD [ "app.handler" ]