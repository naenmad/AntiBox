# ZedGravity Architecture & Design Specification

ZedGravity is an independent, native macOS companion application engineered specifically for **Zed Editor** and **Google Antigravity Agent Client Protocol (ACP)**. It provides real-time multi-account quota monitoring, zero-prompt credential vaulting, and seamless hot-swapping between Google Gemini, Claude Opus/Sonnet, and GPT-OSS models.

---

## 1. System Topology

```mermaid
graph TB
    subgraph "macOS System & Menu Bar"
        MB["ZedGravity MenuBarExtra<br/>(Continuous Live Metrics: G / C / Img)"]
        WIN["ZedGravity Cockpit Window<br/>(SwiftUI + Frosted Glass Vibrancy)"]
        NOTIF["macOS UNUserNotificationCenter<br/>(Foreground Banners & Sounds)"]
    end

    subgraph "Zed Editor & AI Subsystem"
        ZED["Zed Editor (v0.150+)"]
        ACP["agy_acp_server.par<br/>(Agent Client Protocol Server)"]
        TOKEN_FILE["~/.gemini/antigravity-acp/acp_token.json<br/>(Active Token File)"]
        ZED_SETTINGS["~/.config/zed/settings.json<br/>(AGY_ACP_FORCE_FILE_STORAGE: '1')"]
    end

    subgraph "ZedGravity Core Engine"
        DVM["DashboardViewModel<br/>(Reactive State & Smart Sync Scheduler)"]
        SYNC["ZedACPSyncService<br/>(Token Swapper & Hot-Reload Engine)"]
        DIRECT["DirectCloudCodeEngine<br/>(Standalone Google OAuth & Quota Engine)"]
        VAULT["KeychainManager<br/>(POSIX 0600 File Vault - Zero Password Prompts)"]
        STORE["AntiBoxAccountStore<br/>(~Library/Application Support/ZedGravity/)"]
    end

    subgraph "Google Cloud Infrastructure"
        OAUTH["Google OAuth2 Token Service<br/>(https://oauth2.googleapis.com/token)"]
        CLOUD_CODE["Google Cloud Code Internal API<br/>(retrieveUserQuotaSummary & fetchAvailableModels)"]
    end

    WIN --> DVM
    MB --> DVM
    DVM --> SYNC
    DVM --> DIRECT
    DVM --> NOTIF
    SYNC --> TOKEN_FILE
    SYNC --> ACP
    ZED --> ACP
    ACP --> TOKEN_FILE
    ZED --> ZED_SETTINGS
    DIRECT --> OAUTH
    DIRECT --> CLOUD_CODE
    DIRECT --> VAULT
    STORE --> VAULT
```

---

## 2. Token Refresh & Quota Discovery Flow

Unlike traditional proxy servers that require a daemon running on `localhost:8080`, ZedGravity communicates **directly and natively** with Google Cloud Code APIs using official Google OAuth client metadata:

```mermaid
sequenceDiagram
    autonumber
    actor User as Developer / Zed
    participant App as ZedGravity Engine
    participant Vault as POSIX 0600 Vault
    participant GoogleAuth as Google OAuth2 API
    participant CloudCode as Google Cloud Code API
    participant ZedACP as Zed ACP Server

    User->>App: Trigger Refresh (Timer / Manual ⌘R)
    App->>Vault: Retrieve Refresh Token for Active Account
    Vault-->>App: Refresh Token (Decrypted)
    
    App->>GoogleAuth: POST /token (grant_type=refresh_token)
    GoogleAuth-->>App: Return Fresh Access Token (200 OK)
    
    par Query Quota Summary
        App->>CloudCode: POST :retrieveUserQuotaSummary
        CloudCode-->>App: Return Gemini 5h/Weekly & Claude/3P Buckets
    and Query Model Specific Allocations
        App->>CloudCode: POST :fetchAvailableModels
        CloudCode-->>App: Return Flash-Image, Thinking Models, Limits
    end

    App->>App: Compute Authoritative Constraints & Reset Times
    App->>User: Update Menu Bar ("G: 74% • C: 0% • Img: 74%")
```

---

## 3. Zero-Downtime Zed ACP Hot-Reload Mechanism

When ZedGravity switches accounts (either manually or via Intelligent Auto-Switch), it swaps credentials without interrupting Zed's open editor windows or wiping active chat threads:

```mermaid
sequenceDiagram
    autonumber
    participant ZG as ZedGravity Engine
    participant Disk as ~/.gemini/antigravity-acp/acp_token.json
    participant Daemon as agy_acp_server.par
    participant Zed as Zed Editor

    ZG->>Disk: Atomic write new refresh_token & account_id (chmod 0600)
    ZG->>Daemon: Send SIGTERM to running agy_acp_server.par & localharness
    Daemon-->>Daemon: Graceful exit
    Note over Zed,Daemon: Zed detects ACP process termination
    Zed->>Zed: Retain chat history and active buffer state
    User->>Zed: Next Prompt / Message in Zed AI panel
    Zed->>Disk: Read updated acp_token.json
    Zed->>Daemon: Respawn agy_acp_server.par with new account token
    Daemon-->>Zed: Streaming AI response from new account seamlessly
```

---

## 4. Quota Monitoring & Auto-Switch Strategy

ZedGravity provides a configurable strategy engine:

| Strategy Mode | Trigger Condition | Candidate Selection |
| :--- | :--- | :--- |
| **Claude / GPT Only** | Lowest 3P model quota $\le 5\%$ | Highest available Claude quota ($> 5\%$) |
| **Gemini Only** | Gemini remaining quota $\le 5\%$ | Highest available Gemini quota ($> 5\%$) |
| **Both (Dual Guard)** | Either Gemini or Claude $\le 5\%$ | Highest overall capacity where both $> 5\%$ |

---

## 5. Security & Isolation

1. **Zero Prompt Credential Vaulting**: Tokens are stored in private Application Support folders with strict POSIX `0600` permissions, eliminating repetitive macOS Keychain password dialogs.
2. **Zero Network Telemetry**: ZedGravity never makes calls to analytics, tracking servers, or remote third-party relays. All network communication is strictly between your machine and `googleapis.com`.
3. **No Root Privileges**: Operates completely in user-space without background root daemons or `launchd` system agents.
