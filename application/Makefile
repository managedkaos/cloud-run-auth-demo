all: deploy add-secret

deploy:
	gcloud run deploy $(SERVICE_NAME) \
		--source . \
		--project $(PROJECT_ID) \
		--region $(REGION) \
		--allow-unauthenticated

add-secret:
	gcloud secrets versions add firebase-config --data-file="firebase-config.json"
