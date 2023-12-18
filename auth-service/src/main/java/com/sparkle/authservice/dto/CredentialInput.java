package com.sparkle.authservice.dto;

import lombok.Builder;

@Builder
public class CredentialInput {
    public String username;
    public String password;
    public String type;
}
