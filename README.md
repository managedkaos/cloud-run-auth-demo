# Cloud Run and Firebase Demo

A FastAPI based application hosted on Cloud Run that uses Firebase Auth and Firestore.

This guide covers how to configure, deploy, and verify the app.

TODO: Add steps for terraform deployment.

## 1. Firebase Configuration (Critical Step)

Before deploying, you must update the Firebase configuration in `application/templates/login.html`.

1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Select your project (`cloud-run-and-firebase`).
3. Navigate to **Project Settings** > **General**.
4. Scroll down to **Your apps**. If no web app exists, select the `</>` icon to register a new web app.
5. Copy the `firebaseConfig` object (apiKey, authDomain, etc.).
6. Open `application/templates/login.html` and replace the placeholder config with your actual values:

```javascript
  const firebaseConfig = {
    apiKey: "YOUR_API_KEY",
    authDomain: "YOUR_PROJECT_ID.firebaseapp.com",
    projectId: "YOUR_PROJECT_ID",
    // ...
  };
```

## 2. Deployment

A `Makefile` has been provided for easy deployment.

1. Open a terminal in the `./application` directory.
2. Run the deploy command:

   ```bash
   make deploy
   ```

   This command runs: `gcloud run deploy cloud-run-and-firebase --source . --project cloud-run-and-firebase --region us-central1 --allow-unauthenticated`

3. After deployment, the `gcloud` command will output a Service URL (e.g., `https://cloud-run-and-firebase-xyz-uc.a.run.app`). Save this URL for the next steps.

## 3. Google Login Setup

To enable the "Sign in with Google" functionality:

1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Navigate to **Authentication** > **Sign-in method**.
3. Select **Add new provider** and select **Google**.
4. Toggle the **Enable** switch.
5. Provide a **Project support email**.
6. Select **Save**.
7. Select **Authentication** > **Settings** > **Authorized domains**. Add the Cloud Run domain.

## 4. Blocking Functions Setup (Critical for Security)

This project uses a Firebase Auth Blocking Function to restrict access to authorized users only.

> [!IMPORTANT]
> **Firebase Billing**: Blocking functions require the Firebase project to be on the Blaze (pay-as-you-go) plan. Ensure your project is using this plan.
>
> **Manual Configuration**: You must manually enable "Blocking functions" in the Firebase Console after deployment.
>
> **Secret Management**: You will need to add the actual authorized emails to the created Secret in the Google Cloud Console or via CLI. The Terraform configuration will create the Secret with a placeholder value.

1. **Configure Secret**:
    - Go to [Secret Manager](https://console.cloud.google.com/security/secret-manager).
    - Open `auth-allowed-emails`.
    - Select **+ New Version**.
    - Enter a comma-separated list of authorized emails (e.g., `user1@gmail.com,user2@example.com`).
    - Select **Disable all past versions**.
    - Select **Add New Version**.
2. **Enable Blocking Function**:
    - Go to [Firebase Console](https://console.firebase.google.com/) > **Authentication** > **Settings** > **Blocking functions**.
    - Under **Before account creation (beforeCreate)**, select the blocking function that was deployed by Terraform.
    - Toggle **Enable**.
    - Select the deployed function (e.g., `auth-before-create`).
    - Select **Save**.

## 5. Verification Steps

### Create a Test User

1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Navigate to **Authentication** > **Users**.
3. Select **Add user**.
4. Enter an email and password for your test user.
5. Select **Add user**.

### Accessing the App

After deployment, the `gcloud` command will output a Service URL (e.g., `https://cloud-run-and-firebase-xyz-uc.a.run.app`). Open this URL in your browser.

### Login Flow

1. You should be redirected to `/login`.
2. Enter a valid email and password for a user in your Firebase Authentication project.
   > **Note**: You may need to create a user in the Firebase Console > Authentication > Users tab if you haven't already.
3. Select **Sign In**.
4. Upon success, you are redirected to `/dashboard`.

### CRUD Operations

1. On the Dashboard, verify you see "Logged in as: [your email]".
2. Enter a name in "New Item Name" and select **Add Item**.
3. The page will reload, and your new item should appear in the "Item List" below.
4. Refresh the page to confirm the data is persisted in Firestore.

### Logout

1. Select **Logout** in the navigation bar.
2. You should be redirected back to the Login page.
3. Try accessing `/dashboard` directly; you should be redirected to Login.
