FROM rust:1.78-slim
WORKDIR /app
COPY . .
RUN cargo build --release
EXPOSE 8080
CMD ["./target/release/exchange"]