package com.oncovision;

/**
 * Classe simples para formatar a resposta JSON que o API Gateway vai devolver.
 * @author Weriton L. Petreca
 */
public class Response {
    public String message;
    public String pacienteId;
    public String uploadUrl;
    public String bucket;
    public String key;

    public Response(String message, String pacienteId, String uploadUrl, String bucket, String key) {
        this.message = message;
        this.pacienteId = pacienteId;
        this.uploadUrl = uploadUrl;
        this.bucket = bucket;
        this.key = key;
    }
}