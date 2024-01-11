package com.example.productservice;

import com.example.productservice.dto.ProductRequest;
import com.example.productservice.repository.ProductRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.test.web.servlet.result.MockMvcResultMatchers;
import org.testcontainers.containers.MongoDBContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import java.math.BigDecimal;

import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

//import org.testcontainers.shaded.com.google.common.net.MediaType;
@SpringBootTest
@Testcontainers
@AutoConfigureMockMvc
class MicroservicesApplicationTests {

	@Container
	// To use Container be sure to open and login to DockerHub.
	static MongoDBContainer mongoDBContainer = new MongoDBContainer(DockerImageName.parse("mongo:4.0.10"));

//	static MongoDBContainer mongoDBContainer = new MongoDBContainer("mongo:4.0.10");
	@Autowired
	// Mocks the server to take Request and return Response at REST endpoints.
	private MockMvc mockMvc;

	@Autowired
	// Translates object to json.
	private ObjectMapper objectMapper;

	@Autowired
	// This grants tests access to database.
	private ProductRepository productRepository;

	@DynamicPropertySource
	// Sets the properties in this test like the properties in
	// microservices/src/main/resources/application.properties.
	static void setProperties(DynamicPropertyRegistry dynamicPropertyRegistry){
		dynamicPropertyRegistry.add("spring.data.mongodb.uri", mongoDBContainer::getReplicaSetUrl);
	}
	@Test
	void shouldCreateProduct() throws Exception {
		ProductRequest productRequest = GetProductRequest();
		String productRequestString = objectMapper.writeValueAsString(productRequest);
		mockMvc.perform(MockMvcRequestBuilders.post("/api/product")
				.contentType(MediaType.APPLICATION_JSON)
						.content(productRequestString)
				).andExpect(status().isCreated());
		Assertions.assertEquals( 1,productRepository.findAll().size());
	}
	@Test
	void shouldGetProducts() throws Exception {
		ProductRequest productRequest = GetProductRequest();
		String productRequestString = objectMapper.writeValueAsString(productRequest);
		mockMvc.perform(MockMvcRequestBuilders.post("/api/product")
				.contentType(MediaType.APPLICATION_JSON)
				.content(productRequestString)
		);
		mockMvc.perform(MockMvcRequestBuilders.get("/api/product") )
				.andExpectAll(
						MockMvcResultMatchers.status().isOk(),
						MockMvcResultMatchers.jsonPath("$[0].name")
								.value(productRequest.getName()),
						MockMvcResultMatchers.jsonPath("$[0].description")
								.value(productRequest.getDescription()),
						MockMvcResultMatchers.jsonPath("$[0].price")
								.value(productRequest.getPrice())
				) ;
	}

	private ProductRequest GetProductRequest() {
		return ProductRequest.builder()
				.name("iPhone 13")
				.description("iPhone 13")
				.price(BigDecimal.valueOf(1200))
				.build()
				;
	}

}
