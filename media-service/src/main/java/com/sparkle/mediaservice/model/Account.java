package com.sparkle.mediaservice.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.math.BigDecimal;

@Document(value = "account")
@AllArgsConstructor
@NoArgsConstructor
@Builder
@Data
public class Account {
    @Id
    private String id;
    private String orgId;
    private String name;
    private Type type;
    private String accountNumber;
    private String routingNumber;
    private String description;
    private BigDecimal balance;

    public enum Type {
        OFFICE,
        BANK,
        STOCK,
        INSURANCE,
    }
}
