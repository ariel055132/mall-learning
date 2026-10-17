package com.macro.mall.tiny.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * @auther macrozheng
 * @description Swagger文档的配置
 * @date 2022/11/22
 * @github https://github.com/macrozheng
 */
@Configuration
public class SpringDocConfig {

    @Bean
    public OpenAPI mallTinyOpenAPI() {
        return new OpenAPI()
                .info(new Info().title("SwaggerUI演示")
                        .description("mall-tiny")
                        .contact(new Contact().name("macro"))
                        .version("1.0"));
    }

}
