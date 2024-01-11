package com.example.productservice.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

// Creates a constructor using every field in the class.
@AllArgsConstructor
// Creates a constructor without any of class's fields.
@NoArgsConstructor
// Creates the getter/setters API for the class.
@Builder
@Data
public class ProductResponse {
    private String id;
    private String name;
    private String description;
    private BigDecimal price;

}
