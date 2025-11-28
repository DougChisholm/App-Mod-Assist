# Azure Services Architecture Diagram

This document provides a visual overview of the Azure services deployed by this repository and how they connect to each other.

## High-Level Architecture

```mermaid
flowchart TB
    subgraph Users["👥 Users"]
        Browser["🌐 Web Browser"]
    end

    subgraph AzureInfra["☁️ Azure Infrastructure"]
        subgraph Identity["🔐 Identity"]
            MI["User-Assigned<br/>Managed Identity<br/>(mid-expensemgmt-xxx)"]
        end

        subgraph Compute["💻 Compute"]
            AppService["App Service (S1)<br/>(app-expensemgmt-xxx)<br/>.NET 8.0 on Linux"]
        end

        subgraph Data["💾 Data"]
            SQLServer["Azure SQL Server<br/>(sql-expensemgmt-xxx)<br/>Entra ID Auth Only"]
            SQLDb["Azure SQL Database<br/>(Northwind)<br/>Basic Tier"]
        end

        subgraph Monitoring["📊 Monitoring"]
            LogAnalytics["Log Analytics<br/>Workspace<br/>(log-expensemgmt-xxx)"]
            AppInsights["Application<br/>Insights<br/>(appi-expensemgmt-xxx)"]
        end

        subgraph GenAI["🤖 GenAI (Optional)"]
            AOAI["Azure OpenAI<br/>(oai-expensemgmt-xxx)<br/>GPT-4o in Sweden Central"]
            AISearch["Azure AI Search<br/>(srch-expensemgmt-xxx)<br/>Basic Tier"]
        end
    end

    %% User Flow
    Browser -->|HTTPS| AppService

    %% Identity Flow
    AppService -.->|Uses| MI
    MI -.->|Authenticates| SQLServer
    MI -.->|Authenticates| AOAI
    MI -.->|Authenticates| AISearch

    %% Data Flow
    AppService -->|Stored Procedures| SQLDb
    SQLServer --> SQLDb

    %% GenAI Flow
    AppService -->|Chat API| AOAI
    AppService -->|RAG Queries| AISearch

    %% Monitoring Flow
    AppService -.->|Diagnostics| LogAnalytics
    AppService -.->|Telemetry| AppInsights
    SQLServer -.->|Audit Logs| LogAnalytics
    SQLDb -.->|Diagnostics| LogAnalytics
    AppInsights -.->|Stores in| LogAnalytics

    %% Styling
    classDef identity fill:#e1f5fe,stroke:#0288d1
    classDef compute fill:#e8f5e9,stroke:#388e3c
    classDef data fill:#fff3e0,stroke:#f57c00
    classDef monitoring fill:#f3e5f5,stroke:#7b1fa2
    classDef genai fill:#fce4ec,stroke:#c2185b
    classDef user fill:#eceff1,stroke:#607d8b

    class MI identity
    class AppService compute
    class SQLServer,SQLDb data
    class LogAnalytics,AppInsights monitoring
    class AOAI,AISearch genai
    class Browser user
```

## Component Details

### Core Infrastructure (Always Deployed)

| Component | Azure Service | Purpose |
|-----------|--------------|---------|
| **Managed Identity** | User-Assigned Managed Identity | Passwordless authentication between Azure services |
| **Web App** | App Service (S1 Linux) | Hosts the ASP.NET 8.0 Razor Pages application |
| **SQL Server** | Azure SQL Server | Database server with Entra ID authentication only |
| **Database** | Azure SQL Database (Basic) | Stores expense data, users, categories, statuses |
| **Log Analytics** | Log Analytics Workspace | Centralized log collection and analysis |
| **App Insights** | Application Insights | Application performance monitoring |

### GenAI Components (Optional - deploy with `deployGenAI=true`)

| Component | Azure Service | Purpose |
|-----------|--------------|---------|
| **OpenAI** | Azure OpenAI (S0) | GPT-4o model for natural language chat interface |
| **AI Search** | Azure AI Search (Basic) | RAG pattern support for contextual responses |

## Connection Types

| Connection | Authentication Method |
|------------|----------------------|
| App → SQL | Managed Identity (Active Directory Managed Identity) |
| App → OpenAI | Managed Identity (Cognitive Services OpenAI User role) |
| App → AI Search | Managed Identity (Search Index Data Contributor role) |
| User → App | HTTPS (public endpoint) |
| Resources → Log Analytics | Azure Diagnostic Settings |

## Data Flow

### Standard Request Flow
```
User Browser → App Service → SQL Database (via Stored Procedures) → Response
```

### AI Chat Flow (when GenAI deployed)
```
User Browser → App Service → Azure OpenAI (Function Calling) → App Service → SQL Database → Azure OpenAI → Response
```

### Monitoring Flow
```
App Service Logs → Log Analytics Workspace
SQL Server Audit → Log Analytics Workspace
SQL Database Metrics → Log Analytics Workspace
App Telemetry → Application Insights → Log Analytics Workspace
```

## Security Features

1. **No SQL Passwords**: Entra ID authentication only (`azureADOnlyAuthentication: true`)
2. **Managed Identity**: All service-to-service auth uses passwordless managed identity
3. **HTTPS Only**: App Service configured with `httpsOnly: true`
4. **TLS 1.2 Minimum**: Both App Service and SQL Server enforce TLS 1.2+
5. **FTPS Disabled**: App Service file transfer disabled for security

## Regions

| Resource | Region | Reason |
|----------|--------|--------|
| Most Resources | UK South | Primary deployment region |
| Azure OpenAI | Sweden Central | GPT-4o model availability and quota |

## Resource Naming Convention

All resources follow this pattern: `{prefix}-{baseName}-{uniqueSuffix}`

- `{prefix}`: Resource type abbreviation (app, sql, mid, log, appi, oai, srch)
- `{baseName}`: Base name parameter (default: expensemgmt)
- `{uniqueSuffix}`: Generated from `uniqueString(resourceGroup().id)` for deterministic uniqueness
