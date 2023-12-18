package com.sparkle.mediaservice.dto;
import com.sparkle.mediaservice.model.Account;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

@Data           // == @Getter + @Setter
@Builder
@AllArgsConstructor
@NoArgsConstructor

public class AccountResponse {
    private String id;
    private String name;
    private Account.Type type;
    private String accountNumber;
    private String routingNumber;
    private String description;
    private BigDecimal balance;
}
