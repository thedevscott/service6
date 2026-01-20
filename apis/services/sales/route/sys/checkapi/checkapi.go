package checkapi

import (
	"context"
	"encoding/json"
	"net/http"
)

// func liveness(cx context.Context, w http.ResponseWriter, r *http.Request) error {
func liveness(ctx context.Context, w http.ResponseWriter, r *http.Request) error {
	status := struct {
		Status string
	}{
		Status: "OK",
	}

	return json.NewEncoder(w).Encode(status)
}

// func readiness(cx context.Context, w http.ResponseWriter, r *http.Request) error {
func readiness(ctx context.Context, w http.ResponseWriter, r *http.Request) error {
	status := struct {
		Status string
	}{
		Status: "OK",
	}

	return json.NewEncoder(w).Encode(status)
}
