#!/usr/bin/env python3
"""
Block Diagram Generator for Delivery Route Optimization System
Generates Mermaid diagram code for the system architecture
"""

def generate_block_diagram():
    """Generate Mermaid diagram code for the delivery route optimization system"""
    
    diagram_code = """
graph TD
    A[User Input: Addresses] --> B[Frontend Flutter App]
    B --> C[Authentication System]
    C --> D[Address Geocoding]
    D --> E[Route Optimization Engine]
    E --> F[ETA Prediction Model]
    F --> G[Route Visualization]
    G --> H[Optimized Route Output]
    
    subgraph "Stage 1: Data Processing"
        D --> D1[OpenRouteService API]
        D --> D2[Nominatim Fallback]
        D1 --> D3[Coordinate Extraction]
        D2 --> D3
    end
    
    subgraph "Stage 2: Route Optimization"
        E --> E1[Distance Matrix Calculation]
        E1 --> E2[Nearest Neighbor Algorithm]
        E2 --> E3[2-Opt Improvement]
        E3 --> E4[Traffic Multiplier Application]
    end
    
    subgraph "Stage 3: ML Prediction & Output"
        F --> F1[XGBoost Model]
        F1 --> F2[Time-based Features]
        F2 --> F3[Traffic Analysis]
        F3 --> F4[Final ETA Prediction]
    end
    
    I[OCR Module] --> J[Address Extraction]
    J --> D
    
    K[Training Data Collection] --> L[Model Retraining]
    L --> F1
    
    style A fill:#e1f5fe
    style H fill:#c8e6c9
    style F1 fill:#fff3e0
    style E2 fill:#f3e5f5
    style D1 fill:#e8f5e8
"""
    
    return diagram_code

def generate_detailed_flow_diagram():
    """Generate detailed flow diagram showing data flow"""
    
    diagram_code = """
graph LR
    subgraph "Input Layer"
        A1[User Addresses]
        A2[Image Upload]
        A3[User Credentials]
    end
    
    subgraph "Processing Layer"
        B1[Geocoding Service]
        B2[OCR Processing]
        B3[Authentication]
        B4[Route Optimization]
        B5[ML Prediction]
    end
    
    subgraph "Output Layer"
        C1[Optimized Route]
        C2[ETA Prediction]
        C3[Map Visualization]
        C4[User Dashboard]
    end
    
    A1 --> B1
    A2 --> B2
    A3 --> B3
    B1 --> B4
    B2 --> B1
    B3 --> B4
    B4 --> B5
    B5 --> C1
    B5 --> C2
    C1 --> C3
    C2 --> C3
    C3 --> C4
    
    style A1 fill:#e3f2fd
    style A2 fill:#e3f2fd
    style A3 fill:#e3f2fd
    style C1 fill:#e8f5e8
    style C2 fill:#e8f5e8
    style C3 fill:#e8f5e8
    style C4 fill:#e8f5e8
"""
    
    return diagram_code

def generate_ml_pipeline_diagram():
    """Generate ML pipeline diagram"""
    
    diagram_code = """
graph TD
    A[Raw Route Data] --> B[Data Preprocessing]
    B --> C[Feature Engineering]
    C --> D[Train/Test Split]
    D --> E[XGBoost Training]
    E --> F[Model Evaluation]
    F --> G[Model Deployment]
    G --> H[Real-time Prediction]
    
    subgraph "Feature Engineering"
        C --> C1[Time of Day]
        C --> C2[Distance Features]
        C --> C3[Traffic Multipliers]
        C --> C4[Route Complexity]
    end
    
    subgraph "Model Training"
        E --> E1[Hyperparameter Tuning]
        E1 --> E2[Cross Validation]
        E2 --> E3[Performance Metrics]
    end
    
    subgraph "Production"
        H --> H1[ETA Prediction]
        H1 --> H2[Route Optimization]
        H2 --> H3[User Interface]
    end
    
    style A fill:#ffebee
    style G fill:#e8f5e8
    style H3 fill:#e3f2fd
"""
    
    return diagram_code

def save_diagrams():
    """Save all diagrams to files"""
    
    # Main block diagram
    with open('block_diagram.mmd', 'w') as f:
        f.write(generate_block_diagram())
    
    # Detailed flow diagram
    with open('detailed_flow.mmd', 'w') as f:
        f.write(generate_detailed_flow_diagram())
    
    # ML pipeline diagram
    with open('ml_pipeline.mmd', 'w') as f:
        f.write(generate_ml_pipeline_diagram())
    
    print("✅ Diagrams generated successfully!")
    print("Files created:")
    print("- block_diagram.mmd")
    print("- detailed_flow.mmd") 
    print("- ml_pipeline.mmd")
    print("\nTo view diagrams:")
    print("1. Copy the content to https://mermaid.live/")
    print("2. Or use Mermaid CLI: mmdc -i block_diagram.mmd -o block_diagram.png")

def print_diagram_code():
    """Print diagram code to console"""
    
    print("=" * 60)
    print("MAIN BLOCK DIAGRAM")
    print("=" * 60)
    print(generate_block_diagram())
    
    print("\n" + "=" * 60)
    print("DETAILED FLOW DIAGRAM")
    print("=" * 60)
    print(generate_detailed_flow_diagram())
    
    print("\n" + "=" * 60)
    print("ML PIPELINE DIAGRAM")
    print("=" * 60)
    print(generate_ml_pipeline_diagram())

if __name__ == "__main__":
    print("🚀 Delivery Route Optimization System - Diagram Generator")
    print("=" * 60)
    
    # Save diagrams to files
    save_diagrams()
    
    # Print to console
    print_diagram_code()
    
    print("\n" + "=" * 60)
    print("📋 USAGE INSTRUCTIONS:")
    print("=" * 60)
    print("1. Copy any diagram code above")
    print("2. Paste into https://mermaid.live/")
    print("3. Export as PNG/SVG for documentation")
    print("4. Or use in Markdown with: ```mermaid ... ```")
