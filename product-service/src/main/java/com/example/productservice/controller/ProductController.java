package com.example.productservice.controller;

import com.example.productservice.dto.ProductRequest;
import com.example.productservice.dto.ProductResponse;
import com.example.productservice.service.ProductService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;

//Indicates the methods below return data will be
// written to a response body.
@RestController

//Makes the rest endpoint to access the class via GET,POST, etc.
@RequestMapping("/api/product")
@RequiredArgsConstructor

public class ProductController {
    // ProductService can't be accessed(private)
    // nor inherited/extended(final).
    private final ProductService productService;

    // POST requests creates a Product Object and into the database.
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public void createProduct(@RequestBody ProductRequest productRequest){
        productService.createProduct(productRequest);
    }

    // Get request will return a list of the ProductResponse Objects
    // from the MongoDB.
    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    public List<ProductResponse> getAllProducts(){
        return productService.getAllProducts();
    }
}
