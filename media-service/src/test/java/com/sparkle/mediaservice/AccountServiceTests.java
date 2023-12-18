package com.sparkle.mediaservice;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sparkle.mediaservice.dto.AccountRequest;
import com.sparkle.mediaservice.dto.AccountResponse;
import com.sparkle.mediaservice.repository.AccountRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.testcontainers.containers.MongoDBContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import java.io.IOException;
import java.math.BigDecimal;
import java.net.Socket;
import java.net.UnknownHostException;
import java.util.List;

import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@Testcontainers
@AutoConfigureMockMvc
class AccountServiceTests {
	@Container
	static MongoDBContainer mongoDBContainer = new MongoDBContainer(DockerImageName.parse("mongo:4.0.10"))
					.withExposedPorts(27017);
	@Autowired
	private MockMvc mockMvc;
	@Autowired
	private ObjectMapper objectMapper;
	@Autowired
	private AccountRepository accountRepository;

	@DynamicPropertySource
	static void setProperties(DynamicPropertyRegistry dynDynamicPropertyRegistry) {
		dynDynamicPropertyRegistry.add("spring.data.mongodb.uri", mongoDBContainer::getReplicaSetUrl);
	}

	@BeforeAll
	static void initAll() {
		mongoDBContainer.start();
	}

	@AfterEach
	void cleanUp() {
		this.accountRepository.deleteAll();
	}

	@Test
	void contextLoads() {
	}

	@Test
	void containerStartsAndPublicPortIsAvailable() {
		assertThatPortIsAvailable(mongoDBContainer);
	}

	private void assertThatPortIsAvailable(MongoDBContainer mongoDBContainer) {
		try {
			new Socket(mongoDBContainer.getContainerIpAddress(), mongoDBContainer.getFirstMappedPort());
		} catch (UnknownHostException e) {
			throw new RuntimeException(e);
		} catch (IOException e) {
			throw new AssertionError("Port connection failed: "
					+ mongoDBContainer.getFirstMappedPort() + ". "+ e);
		}
	}

	@Test
	void shouldCreateAccount() throws Exception {
		AccountRequest accountRequest = getAccountRequest();
		mockMvc.perform(MockMvcRequestBuilders.post("/api/account")
					.contentType(MediaType.APPLICATION_JSON)
					.content(objectMapper.writeValueAsString(accountRequest)))
				.andExpect(status().isCreated());
		Assertions.assertEquals(1, accountRepository.findAll().size());
	}

	@Test
	void getAccount() throws Exception {
		AccountRequest accountRequest = getAccountRequest();
		mockMvc.perform(MockMvcRequestBuilders.post("/api/account")
						.contentType(MediaType.APPLICATION_JSON)
						.content(objectMapper.writeValueAsString(accountRequest)))
				.andExpect(status().isCreated());
		Assertions.assertTrue(accountRepository.findAll().size() >= 1);

		ResultActions resultActions = mockMvc.perform(MockMvcRequestBuilders.get("/api/account")
						.contentType(MediaType.APPLICATION_JSON))
				.andExpect(status().isOk());
		MvcResult result = resultActions.andReturn();
		String contentAsString = result.getResponse().getContentAsString();
		List<AccountResponse> accountResponses = objectMapper.readValue(contentAsString,
				new TypeReference<List<AccountResponse>>(){});			// Sweet!
		Assertions.assertTrue(accountResponses.stream()
				.filter(s -> s.getName() != null)
				.anyMatch(s -> s.getName().equals("Amazon")));
	}

	private AccountRequest getAccountRequest() {
		return AccountRequest.builder()
				.name("Amazon")
				.description("Little shop")
				.balance(BigDecimal.valueOf(1000))
				.build();
	}


}
