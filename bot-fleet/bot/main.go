package main

import (
    "bytes"
    "encoding/json"
    "flag"
    "fmt"
    "math/rand"
    "net/http"
    "sync"
    "time"
)

type Order struct {
    Type     string  `json:"type"`      
    Symbol   string  `json:"symbol"`
    Side     string  `json:"side"`    
    Price    float64 `json:"price"`
    Quantity int     `json:"quantity"`
    OrderID  string  `json:"orderId"`
}

func runBot(targetURL string, botID int, wg *sync.WaitGroup, results chan<- BotResult) {
    defer wg.Done()
    client := &http.Client{Timeout: 5 * time.Second}
    
    for i := 0; i < 1000; i++ {
        order := Order{
            Type:     randomOrderType(),
            Symbol:   "AAPL",
            Side:     randomSide(),
            Price:    100 + rand.Float64()*10,
            Quantity: rand.Intn(100) + 1,
            OrderID:  fmt.Sprintf("bot%d-ord%d", botID, i),
        }
        
        start := time.Now()
        body, _ := json.Marshal(order)
        resp, err := client.Post(targetURL+"/order", "application/json", bytes.NewBuffer(body))
        latency := time.Since(start).Milliseconds()
        
        results <- BotResult{BotID: botID, Latency: latency, Error: err, StatusCode: resp.StatusCode}
        
        time.Sleep(time.Duration(rand.Intn(10)) * time.Millisecond)
    }
}

func main() {
    target := flag.String("target", "http://localhost:8080", "Contestant endpoint")
    bots   := flag.Int("bots", 100, "Number of concurrent bots")
    flag.Parse()
    
    var wg sync.WaitGroup
    results := make(chan BotResult, *bots*1000)
    
    for i := 0; i < *bots; i++ {
        wg.Add(1)
        go runBot(*target, i, &wg, results)
    }
    
    wg.Wait()
    close(results)
    
}