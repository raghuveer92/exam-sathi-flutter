# ExamSaathi Flutter Integration Test Framework

A modular, scalable, CI-ready automation framework for the ExamSaathi Student App.

> Designed to simulate real user behavior using a testing agent approach.
> Fully independent of Cursor after setup.

---

## 📁 Folder Structure

integration_test/
├── app_test.dart              # Main test runner (all flows)
├── config/
│   └── test_config.dart       # Environment & timeouts
├── flows/
│   ├── auth_flow.dart         # Flow 1: signup + OTP
│   ├── onboarding_flow.dart   # Flow 2: exam onboarding
│   ├── study_flow.dart        # Flow 3: study progress
│   └── account_lifecycle_flow.dart  # Flow 4: logout/login/delete
├── robot/
│   ├── test_agent.dart        # User-like testing agent
│   ├── ui_actions.dart        # tap, enterText, scroll, back
│   ├── ui_finder.dart         # Smart finder (key → text → type)
│   └── validator.dart         # assertVisible, assertApiSuccess
├── helpers/
│   ├── otp_helper.dart        # Dev OTP bypass (999999)
│   ├── test_user_generator.dart
│   ├── wait_helper.dart       # Waits + retry (max 2)
│   └── test_reporter.dart     # Logging + JSON report
└── reports/
    ├── example_report.json
    └── latest_report.json

---

App-side keys live in:
lib/core/testing/test_keys.dart

---

## ⚙️ Prerequisites

### Backend

The run script **starts the backend automatically** (dev profile, OTP `999999`) if it is not already up.

Requirements:

- `backend_springboot/.env` configured (copy from `.env.example`)
- Maven (`mvn`) on your PATH

Optional env vars:

| Variable | Default | Purpose |
|----------|---------|---------|
| `SKIP_BACKEND_START=1` | `0` | Use an already-running backend; fail if unreachable |
| `KEEP_BACKEND_RUNNING=1` | `0` | Leave backend running after tests finish |

Manual start (optional):

    cd backend_springboot
    set -a && source .env && set +a
    mvn spring-boot:run -Dspring-boot.run.profiles=dev

### Chrome WebDriver

`flutter drive` on Chrome requires **chromedriver** on port `4444`. The run script installs it automatically via npm, or use Homebrew:

    brew install chromedriver

---

## 🚀 Run Tests (Chrome Only)

`flutter test integration_test -d chrome` is **not supported** by Flutter yet (`Web devices are not supported for integration tests yet`). Use **`flutter drive`** instead:

```bash
cd student_app_flutter

# Starts backend → chromedriver → Chrome tests (all-in-one)
./scripts/run_integration_chrome.sh
```

The script will:

1. Start backend (dev profile) if not already running
2. Wait for `/actuator/health` → UP
3. Start chromedriver on port 4444
4. Run `flutter drive` on Chrome

Or run manually (backend must already be up):
flutter drive \
  --driver=integration_test/driver.dart \
  --target=integration_test/app_test.dart \
  -d chrome \
  --dart-define=INTEGRATION_TEST=true \
  --dart-define=TEST_ENV=dev \
  --dart-define=API_BASE_URL=http://localhost:8080/api/v1
```

---

## 🌐 Why Chrome Only

- Fast execution (no emulator)
- CI/CD friendly
- Stable UI automation
- Low cost
- Easy debugging

---

## 🔐 OTP Bypass

Environment → OTP

dev/test → 999999

Usage:

    OtpHelper.getOtp(email)

Backend must enable:

    app:
      otp:
        use-fixed: true

---

## 👤 Test User Strategy

    TestUserGenerator.generate()

Example:

    email: test_1700000000@examsaathi.test
    password: Test@123456

---

## 🧪 Test Flow Coverage

### 1. Auth Flow
- Signup
- OTP verification
- Login

### 2. Onboarding Flow
- Select exam
- Save profile
- Sync data

### 3. Study Flow
- Exam → Subject → Chapter → Topic
- Add hours
- Mark complete
- Validate progress

### 4. Account Lifecycle Flow
- Logout
- Login again
- Delete account
- Verify login failure

---

## 🧠 Testing Agent

Fallback order:

    Key → Text → Widget Type → Widget Tree

---

## 📊 Reporting

Output:

    integration_test/reports/latest_report.json

Includes:
- Step logs
- Pass/fail status
- Execution time
- Screenshots (on failure)

---

## ⚡ Stability Features

- Smart waits
- Retry (max 2)
- API sync awareness
- Stable key-based selectors

---

## 🔄 CI/CD (Chrome Only)

GitHub Actions:

    - name: Run Integration Tests (Chrome)
      run: |
        cd student_app_flutter
        ./scripts/run_integration_chrome.sh
      env:
        API_BASE_URL: http://localhost:8080/api/v1
        TEST_ENV: test

---

## 🧩 Design Principles

- No emulator dependency
- Chrome-only execution
- Fully modular flows
- Reusable test agent
- CI/CD ready
- Cursor-independent

---

## ❌ Removed Scope

- Android emulator testing
- iOS simulator testing
- Physical device testing

Only Chrome is supported.

---

## ✅ Success Criteria

- Auth flow works
- OTP bypass works
- Exam onboarding works
- Study flow works
- Account lifecycle works
- Runs successfully on Chrome
- CI pipeline stable

---

## 📌 Future Evolution

- Self-healing UI testing system
- AI-driven testing agent
- Full regression CI pipeline
- Large-scale user simulation testing