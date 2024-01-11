package com.example.productservice.service;

import com.example.productservice.dto.ProductRequest;
import com.example.productservice.dto.ProductResponse;
import com.example.productservice.model.Product;
import com.example.productservice.repository.ProductRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
// Automatically creates the constructors for the used classes.
@RequiredArgsConstructor
@Slf4j

public class ProductService {
    // ProductRepository must be initialized which would require manually adding
    // its constructor to this class and all others referencing it but
    // using @RequiredArgConstructor work around this issue.
    private final ProductRepository productRepository;

    // Given a ProductRequest, create Product Object
    // and save it to the MongoDB.
    public void createProduct(ProductRequest productRequest){
        Product product = Product.builder()
                .name(productRequest.getName())
                .description(productRequest.getDescription())
                .price(productRequest.getPrice())
                .build();

        productRepository.save(product);
        log.info("Product {} is saved", product.getId());
    }

//  Return a list of products.
    public List<ProductResponse> getAllProducts() {

        // Get all products from the repo.
        List<Product> products =  productRepository.findAll();

        // Create ProductResponses from each of the products and
        // the return them as a list.
        return products.stream().map(this::mapToProductResponse).toList();
    }
    // Create & return a ProductResponse Object given Product Object.
    private ProductResponse mapToProductResponse(Product product){
        return ProductResponse.builder()
                .id(product.getId())
                .name(product.getName())
                .description(product.getDescription())
                .price(product.getPrice())
                .build();
    }
}
