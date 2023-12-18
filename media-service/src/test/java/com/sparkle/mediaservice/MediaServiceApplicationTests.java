package com.sparkle.mediaservice;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sparkle.mediaservice.dto.MediaRequest;
import com.sparkle.mediaservice.dto.MediaRequest;
import com.sparkle.mediaservice.dto.MediaResponse;
import com.sparkle.mediaservice.model.Media;
import com.sparkle.mediaservice.repository.MediaRepository;
import com.sparkle.mediaservice.repository.MediaRepository;
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
//import org.testcontainers.shaded.com.fasterxml.jackson.databind.ObjectMapper;
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
class MediaServiceApplicationTests {
	@Container
	static MongoDBContainer mongoDBContainer = new MongoDBContainer(DockerImageName.parse("mongo:4.0.10"))
					.withExposedPorts(27017);
	@Autowired
	private MockMvc mockMvc;
	@Autowired
	private ObjectMapper objectMapper;
	@Autowired
	private MediaRepository mediaRepository;

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
		this.mediaRepository.deleteAll();
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

	// CF: See also testcontainers.org/modules/databases/mongodb
	// Youtube: Spring Boot testing tutorial
	// https://rieckpil.de/mongodb-testcontainers-setup-for-datamongotest/

	@Test
	void shouldCreateMedia() throws Exception {
		MediaRequest mediaRequest = getMediaRequest();
		mockMvc.perform(MockMvcRequestBuilders.post("/api/media")
					.contentType(MediaType.APPLICATION_JSON)
					.content(objectMapper.writeValueAsString(mediaRequest)))
				.andExpect(status().isCreated());
		//Assertions.assertEquals(1, mediaRepository.findAll().size());
		Assertions.assertTrue(mediaRepository.findAll().size() >= 1);
	}

	@Test
	void getMedia() throws Exception {
		MediaRequest mediaRequest = getMediaRequest();
		mockMvc.perform(MockMvcRequestBuilders.post("/api/media")
						.contentType(MediaType.APPLICATION_JSON)
						.content(objectMapper.writeValueAsString(mediaRequest)))
				.andExpect(status().isCreated());
		Assertions.assertTrue(mediaRepository.findAll().size() >= 1);

		ResultActions resultActions = mockMvc.perform(MockMvcRequestBuilders.get("/api/media")
						.contentType(MediaType.APPLICATION_JSON))
				.andExpect(status().isOk());
		MvcResult result = resultActions.andReturn();
		String contentAsString = result.getResponse().getContentAsString();
		// MediaResponse[] mediaResponses = objectMapper.readValue(contentAsString, MediaResponse[].class);
		List<MediaResponse> mediaResponses = objectMapper.readValue(contentAsString,
				new TypeReference<List<MediaResponse>>(){});			// Sweet!
		Assertions.assertTrue(mediaResponses.stream()
				.filter(s -> s.getTitle() != null)
				.anyMatch(s -> s.getTitle().equals("HALO")));
	}

	private MediaRequest getMediaRequest() {
		return MediaRequest.builder()
				.title("HALO")
				.artist("Beyonce")
				.year(2020)
				.build();
	}
}
