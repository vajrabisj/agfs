docker build -f docker-image/Dockerfile -t agfs-server-with-plugins .

docker run --rm \
    --name agfs-server \
    -p 8080:8080 \
    -e PERPLEXITY_API_KEY="$PERPLEXITY_API_KEY" \
    -e OLLAMA_URL="http://host.docker.internal:11434" \
    -v /Users/vajra/agfs/plugins:/data \
    c4pt0r/agfs-server:latest


curl -X POST http://localhost:8080/api/v1/plugins/load \
    -H "Content-Type: application/json" \
    -d '{"library_path":"/data/simpcurlfs/libsimpcurlfs.so"}'

curl -X POST http://localhost:8080/api/v1/plugins/load \
    -H "Content-Type: application/json" \
    -d '{"library_path":"/data/summaryfs/libsummaryfs.so"}'

mount simpcurlfs /web api_key_env=PERPLEXITY_API_KEY default_max_results=3

mount summaryfs /summary model=qwen3:4b ollama_url=http://localhost:11434 timeout_ms=120000

echo '{"query":"example"}' > /web/request
cat /web/response.txt

echo 'Just summarize this raw note...' > /summary/request
cat /summary/response.txt
