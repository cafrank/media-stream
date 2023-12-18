package com.sparkle.authservice;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.ObjectWriter;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.sparkle.authservice.dto.CredentialInput;
import com.sparkle.authservice.dto.UserResponse;
import com.sparkle.authservice.model.User;
import com.sparkle.authservice.repository.UserRepository;
import lombok.extern.slf4j.Slf4j;
import org.junit.Before;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Arrays;
import java.util.List;

import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

// https://www.youtube.com/watch?v=VfwP3GOridU

@SpringBootTest
@Testcontainers
@AutoConfigureMockMvc
@Slf4j
class AuthServiceApplicationTests extends ContainersEnvironment {
	@Autowired
	private MockMvc mockMvc;
	@Autowired
	private ObjectMapper objectMapper;
	@Autowired
	private UserRepository userRepo;

	@Test
	void contextLoads() {
	}

	@Before
	void setup() {
		User user = User.builder()
				//        .id(1L)
				.username("cfrank0")
				.password("bar")
				.email("cfrank@osafo.com")
				.firstName("Colin")
				.lastName ("Frank")
				//.attrList(Arrays.asList(attr))
				.build();
		userRepo.save(user);
	}

	@Test
	void getUserList() throws Exception {
		ResultActions resultActions = mockMvc.perform(MockMvcRequestBuilders.get("/api/auth/user")
						.contentType(MediaType.APPLICATION_JSON))
				.andExpect(status().isOk());
		MvcResult result = resultActions.andReturn();
		String contentAsString = result.getResponse().getContentAsString();
		List<UserResponse> AuthList = objectMapper.readValue(contentAsString,
				new TypeReference<List<UserResponse>>(){});						// Sweet!
		Assertions.assertEquals(3, AuthList.size());
	}

	@Test
	void postIsValid() throws Exception {
		CredentialInput cred = CredentialInput.builder().username("cfrank0@osafo.com").password("foo").build();
		ObjectMapper mapper = new ObjectMapper();
		mapper.configure(SerializationFeature.WRAP_ROOT_VALUE, false);
		ObjectWriter ow = mapper.writer().withDefaultPrettyPrinter();
		String requestJson=ow.writeValueAsString(cred);

		ResultActions resultActions = mockMvc.perform(MockMvcRequestBuilders.post("/api/auth/isValid")
						.contentType(MediaType.APPLICATION_JSON)
						.content(requestJson))
				.andExpect(status().isOk());
		MvcResult result = resultActions.andReturn();
		String contentAsString = result.getResponse().getContentAsString();
		log.info(contentAsString);
		Assertions.assertEquals("true", contentAsString);
	}

	@Test
	void postIsValidFail() throws Exception {
		CredentialInput cred = CredentialInput.builder().username("cfrank0").password("fooX").build();
		ObjectMapper mapper = new ObjectMapper();
		mapper.configure(SerializationFeature.WRAP_ROOT_VALUE, false);
		ObjectWriter ow = mapper.writer().withDefaultPrettyPrinter();
		String requestJson=ow.writeValueAsString(cred);

		ResultActions resultActions = mockMvc.perform(MockMvcRequestBuilders.post("/api/auth/isValid")
						.contentType(MediaType.APPLICATION_JSON)
						.content(requestJson))
				.andExpect(status().isOk());
		MvcResult result = resultActions.andReturn();
		String contentAsString = result.getResponse().getContentAsString();
		log.info(contentAsString);
		Assertions.assertEquals("false", contentAsString);
	}

	@Test
	void getUserCount() throws Exception {
		ResultActions resultActions = mockMvc.perform(MockMvcRequestBuilders.get("/api/auth/count")
						.contentType(MediaType.APPLICATION_JSON))
				.andExpect(status().isOk());
		MvcResult result = resultActions.andReturn();
		String contentAsString = result.getResponse().getContentAsString();
		log.info(contentAsString);
		Assertions.assertEquals("3", contentAsString);
	}

}
