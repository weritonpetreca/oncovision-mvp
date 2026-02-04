package com.oncovision;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.google.gson.Gson;
import com.oncovision.dto.PatientRequest;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.GetItemResponse;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.PresignedPutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

public class LambdaHandler implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private static final Region REGION = Region.US_EAST_1;
    private final DynamoDbClient dynamoDb = DynamoDbClient.builder().region(REGION).build();
    private final S3Presigner presigner = S3Presigner.builder().region(REGION).build();
    private final Gson gson = new Gson();

    private final String TABLE_NAME = System.getenv("TABLE_NAME");
    private final String BUCKET_NAME = System.getenv("BUCKET_NAME");

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent input, Context context) {
        Map<String, String> headers = new HashMap<>();
        headers.put("Content-Type", "application/json");
        headers.put("Access-Control-Allow-Origin", "*");
        headers.put("Access-Control-Allow-Methods", "POST,GET,OPTIONS");

        try {
            String method = input.getHttpMethod();
            context.getLogger().log("🚀 Método recebido: " + method);

            if ("POST".equalsIgnoreCase(method)) {
                return handlePost(input, context, headers);
            } else if ("GET".equalsIgnoreCase(method)) {
                return handleGet(input, context, headers);
            } else {
                return new APIGatewayProxyResponseEvent().withStatusCode(405).withHeaders(headers).withBody("Method Not Allowed");
            }

        } catch (Exception e) {
            context.getLogger().log("❌ Erro Crítico: " + e.getMessage());
            e.printStackTrace();
            return new APIGatewayProxyResponseEvent().withStatusCode(500).withHeaders(headers).withBody("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    // --- Lógica de POST (Cadastro) ---
    private APIGatewayProxyResponseEvent handlePost(APIGatewayProxyRequestEvent input, Context context, Map<String, String> headers) {
        if (input.getBody() == null) return errorResponse(400, "Body vazio", headers);

        PatientRequest request = gson.fromJson(input.getBody(), PatientRequest.class);
        String pacienteId = UUID.randomUUID().toString();

        salvarNoDynamo(pacienteId, request);
        String uploadUrl = gerarUrlAssinada(pacienteId);

        Response resp = new Response("Paciente cadastrado", pacienteId, uploadUrl, BUCKET_NAME, "exames/" + pacienteId + ".jpg");
        return new APIGatewayProxyResponseEvent().withStatusCode(200).withHeaders(headers).withBody(gson.toJson(resp));
    }

    // --- Lógica de GET (Consulta) ---
    private APIGatewayProxyResponseEvent handleGet(APIGatewayProxyRequestEvent input, Context context, Map<String, String> headers) {
        // O ID vem na URL: /pacientes/{id} -> pathParameters
        Map<String, String> pathParams = input.getPathParameters();
        if (pathParams == null || !pathParams.containsKey("id")) {
            return errorResponse(400, "ID do paciente obrigatorio na URL", headers);
        }

        String id = pathParams.get("id");

        // Buscar no DynamoDB
        GetItemResponse response = dynamoDb.getItem(GetItemRequest.builder()
                .tableName(TABLE_NAME)
                .key(Map.of("pacienteId", AttributeValue.builder().s(id).build()))
                .build());

        if (!response.hasItem()) {
            return errorResponse(404, "Paciente nao encontrado", headers);
        }

        // Converter o mapa do DynamoDB para um JSON simples manualmente para o retorno
        Map<String, AttributeValue> item = response.item();
        Map<String, Object> resultado = new HashMap<>();
        resultado.put("pacienteId", item.get("pacienteId").s());
        resultado.put("status", item.get("status").s());

        if (item.containsKey("risco")) resultado.put("risco", item.get("risco").s());
        if (item.containsKey("score")) resultado.put("score", item.get("score").n());
        if (item.containsKey("nome")) resultado.put("nome", item.get("nome").s());

        return new APIGatewayProxyResponseEvent().withStatusCode(200).withHeaders(headers).withBody(gson.toJson(resultado));
    }

    private void salvarNoDynamo(String id, PatientRequest req) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("pacienteId", AttributeValue.builder().s(id).build());
        String nomeSafe = (req.getNome() != null && !req.getNome().isEmpty()) ? req.getNome() : "Desconhecido";
        item.put("nome", AttributeValue.builder().s(nomeSafe).build());
        item.put("idade", AttributeValue.builder().n(String.valueOf(req.getIdade())).build());
        String historicoSafe = (req.getHistorico() != null) ? req.getHistorico() : "Nao Informado";
        item.put("historico", AttributeValue.builder().s(historicoSafe).build());
        item.put("status", AttributeValue.builder().s("PENDENTE").build());
        item.put("criadoEm", AttributeValue.builder().s(String.valueOf(System.currentTimeMillis())).build());

        dynamoDb.putItem(PutItemRequest.builder().tableName(TABLE_NAME).item(item).build());
    }

    private String gerarUrlAssinada(String id) {
        String keyName = "exames/" + id + ".jpg";
        PutObjectRequest objectRequest = PutObjectRequest.builder()
                .bucket(BUCKET_NAME).key(keyName).contentType("image/jpeg").build();
        PutObjectPresignRequest presignRequest = PutObjectPresignRequest.builder()
                .signatureDuration(Duration.ofMinutes(15)).putObjectRequest(objectRequest).build();
        return presigner.presignPutObject(presignRequest).url().toString();
    }

    private APIGatewayProxyResponseEvent errorResponse(int statusCode, String message, Map<String, String> headers) {
        return new APIGatewayProxyResponseEvent().withStatusCode(statusCode).withHeaders(headers).withBody("{\"error\": \"" + message + "\"}");
    }
}