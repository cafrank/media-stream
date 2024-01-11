package com.example.productservice.repository;

import com.example.productservice.model.Product;
import org.springframework.data.mongodb.repository.MongoRepository;

// When creating an Interface repo should have the <model class, model's id>
public interface ProductRepository extends MongoRepository<Product, String> {
}
