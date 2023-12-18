package com.sparkle.authservice;

import com.sparkle.authservice.model.User;
import com.sparkle.authservice.repository.UserRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.netflix.eureka.EnableEurekaClient;
import org.springframework.context.annotation.Bean;
import java.util.Map;

@SpringBootApplication
@EnableEurekaClient
public class AuthServiceApplication {

	public static void main(String[] args) {
		SpringApplication.run(AuthServiceApplication.class, args);
	}
	static final Map<String, String> INV_MAP = Map.of(
			"cfrank0@osafo.com", "foo",
			"cfrank2@osafo.com", "foo",
			"cfrank1@osafo.com", "foo"
	);

	@Bean
	public CommandLineRunner loadData(UserRepository UserRepository) {
		return args -> {
			UserRepository.deleteAll();
			INV_MAP.keySet().stream()
					.map(i -> User.builder().username(i)
							.password(INV_MAP.get(i))
							.email(i).firstName("Colin...").lastName("Frank...")
							.build())
					.forEach(UserRepository::save);		// Nice! i -> UserRepository.save(i)
		};
	}
}
