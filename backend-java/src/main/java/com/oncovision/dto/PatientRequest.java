package com.oncovision.dto;

/**
 * Representa os dados enviados pelo médico/frontend.
 * Mantemos simples para o MVP.
 *
 * @author Weriton L. Petreca
 */
public class PatientRequest {
    private String nome;
    private int idade;
    private String historico; // "Sim" ou "Nao"

    // Construtor vazio necessário para o Gson fazer o parse
    public PatientRequest() {}

    public PatientRequest(String nome, int idade, String historico) {
        this.nome = nome;
        this.idade = idade;
        this.historico = historico;
    }

    public String getNome() { return nome; }
    public int getIdade() { return idade; }
    public String getHistorico() { return historico; }
}