package utils

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

// UploadGistIfNeeded checks environment variables and uploads the result file to GitHub Gist
func UploadGistIfNeeded(resultFile, testPort string) {
	gistToken := os.Getenv("GIST_TOKEN")
	gistID := os.Getenv("GIST_ID")

	if gistToken == "" || gistID == "" {
		// Silent skip if env vars are missing
		return
	}

	if resultFile == "" {
		resultFile = "result.csv"
	}

	content, err := os.ReadFile(resultFile)
	if err != nil {
		fmt.Printf("[gist] Result file not found or read error: %v, skip upload.\n", err)
		return
	}

	description := os.Getenv("GIST_DESCRIPTION")
	if description == "" {
		if testPort == "" {
			testPort = "443"
		}
		loc, _ := time.LoadLocation("Asia/Shanghai")
		if loc == nil {
			loc = time.FixedZone("UTC+8", 8*3600)
		}
		description = fmt.Sprintf("CloudflareSpeedTest result [tp=%s] %s", testPort, time.Now().In(loc).Format("2006-01-02 15:04:05 UTC+8"))
	}

	filename := os.Getenv("GIST_FILENAME")

	err = patchGist(gistToken, gistID, filename, description, string(content))
	if err != nil {
		fmt.Printf("[gist] Upload failed: %v\n", err)
	}
}

type gistFile struct {
	Content *string `json:"content"`
}

type gistPatchReq struct {
	Description string              `json:"description,omitempty"`
	Files       map[string]gistFile `json:"files"`
}

type gistResp struct {
	Files   map[string]interface{} `json:"files"`
	HTMLURL string                 `json:"html_url"`
}

func patchGist(token, id, targetFilename, description, content string) error {
	client := &http.Client{Timeout: 15 * time.Second}
	url := "https://api.github.com/gists/" + id

	// 1. Get existing gist meta to find dynamic filename if not provided
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to fetch gist meta: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("github api returned status %d on get", resp.StatusCode)
	}

	var meta gistResp
	if err := json.NewDecoder(resp.Body).Decode(&meta); err != nil {
		return fmt.Errorf("failed to decode gist meta: %w", err)
	}

	if targetFilename == "" {
		for k := range meta.Files {
			targetFilename = k
			break // just take the first one
		}
		if targetFilename == "" {
			targetFilename = "result.csv"
		}
	}

	// Prepare payload: set content for target, null for others to delete them
	files := make(map[string]gistFile)
	for k := range meta.Files {
		if k != targetFilename {
			files[k] = gistFile{Content: nil}
		}
	}
	files[targetFilename] = gistFile{Content: &content}

	payload := gistPatchReq{
		Description: description,
		Files:       files,
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	// 2. Patch gist
	req, _ = http.NewRequest("PATCH", url, bytes.NewBuffer(bodyBytes))
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("Content-Type", "application/json")

	resp, err = client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to patch gist: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("github api returned status %d on patch: %s", resp.StatusCode, string(body))
	}

	var patchResp gistResp
	if err := json.NewDecoder(resp.Body).Decode(&patchResp); err == nil && patchResp.HTMLURL != "" {
		fmt.Printf("[gist] Upload success: %s\n", patchResp.HTMLURL)
	} else {
		fmt.Printf("[gist] Upload finished, but no html_url returned.\n")
	}

	return nil
}
