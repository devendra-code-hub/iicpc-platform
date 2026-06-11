FROM gcc:13-bookworm
WORKDIR /app
COPY . .
RUN g++ -O2 -o exchange main.cpp -lpthread
EXPOSE 8080
CMD ["./exchange"]
