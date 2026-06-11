package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
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
	BotID    int     `json:"botId"`
}

type BotResult struct {
	BotID      int
	OrderID    string
	LatencyMs  int64
	StatusCode int
	Error      string
}

func randomOrderType() string {
	types := []string{"limit", "limit", "limit", "market", "cancel"}
	return types[rand.Intn(len(types))]
}

func randomSide() string {
	if rand.Intn(2) == 0 { return "buy" }
	return "sell"
}

func runBot(targetURL string, botID int, ordersPerBot int, wg *sync.WaitGroup, results chan<- BotResult) {
	defer wg.Done()
	client := &http.Client{Timeout: 5 * time.Second}

	for i := 0; i < ordersPerBot; i++ {
		order := Order{
			Type:     randomOrderType(),
			Symbol:   "AAPL",
			Side:     randomSide(),
			Price:    100.0 + rand.Float64()*10.0,
			Quantity: rand.Intn(100) + 1,
			OrderID:  fmt.Sprintf("bot%d-ord%d", botID, i),
			BotID:    botID,
		}

		body, _ := json.Marshal(order)
		start := time.Now()
		resp, err := client.Post(targetURL+"/order", "application/json", bytes.NewBuffer(body))
		latency := time.Since(start).Milliseconds()

		result := BotResult{BotID: botID, OrderID: order.OrderID, LatencyMs: latency}
		if err != nil {
			result.Error = err.Error()
		} else {
			result.StatusCode = resp.StatusCode
			resp.Body.Close()
		}
		results <- result
		time.Sleep(time.Duration(rand.Intn(10)) * time.Millisecond)
	}
}

func main() {
	target       := flag.String("target", "http://localhost:8080", "Contestant endpoint URL")
	botCount     := flag.Int("bots", 100, "Number of concurrent bots")
	ordersPerBot := flag.Int("orders", 500, "Orders per bot")
	flag.Parse()

	log.Printf("Starting %d bots → %s (%d orders each)", *botCount, *target, *ordersPerBot)

	var wg sync.WaitGroup
	results := make(chan BotResult, (*botCount)*(*ordersPerBot))

	start := time.Now()
	for i := 0; i < *botCount; i++ {
		wg.Add(1)
		go runBot(*target, i, *ordersPerBot, &wg, results)
	}

	wg.Wait()
	close(results)
	elapsed := time.Since(start).Seconds()

	var totalOrders, errors int
	var totalLatency int64
	for r := range results {
		totalOrders++
		totalLatency += r.LatencyMs
		if r.Error != "" { errors++ }
	}

	avgLatency := float64(totalLatency) / float64(totalOrders)
	tps := float64(totalOrders) / elapsed

	log.Printf("=== RESULTS ===")
	log.Printf("Total orders: %d", totalOrders)
	log.Printf("Errors: %d", errors)
	log.Printf("Avg latency: %.2fms", avgLatency)
	log.Printf("TPS: %.2f", tps)
	log.Printf("Duration: %.2fs", elapsed)
}
