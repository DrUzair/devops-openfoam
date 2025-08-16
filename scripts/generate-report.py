#!/usr/bin/env python3
"""
OpenFOAM Parametric Study Report Generator
Creates comprehensive HTML report of simulation results
"""

import os
import sys
import json
import pandas as pd
from pathlib import Path
from datetime import datetime
import matplotlib.pyplot as plt
import seaborn as sns

def generate_summary_plots(results_dir):
    """Generate summary plots for all Reynolds numbers"""
    
    summary_file = Path(results_dir) / "summary.csv"
    if not summary_file.exists():
        print(f"Warning: Summary file not found: {summary_file}")
        return
    
    # Read summary data
    df = pd.read_csv(summary_file)
    print(f"Processing {len(df)} simulation results")
    
    # Set style
    plt.style.use('seaborn-v0_8')
    
    # Create summary plots
    fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 12))
    
    # Plot 1: Success Rate
    success_counts = df['Status'].value_counts()
    ax1.pie(success_counts.values, labels=success_counts.index, autopct='%1.1f%%')
    ax1.set_title('Simulation Success Rate')
    
    # Plot 2: Runtime vs Reynolds Number
    successful_df = df[df['Status'] == 'SUCCESS']
    if not successful_df.empty and 'Runtime' in successful_df.columns:
        ax2.plot(successful_df['Reynolds'], successful_df['Runtime'], 'bo-', linewidth=2, markersize=8)
        ax2.set_xlabel('Reynolds Number')
        ax2.set_ylabel('Runtime (seconds)')
        ax2.set_title('Computational Time vs Reynolds Number')
        ax2.grid(True, alpha=0.3)
    
    # Plot 3: Final Residual vs Reynolds Number
    if not successful_df.empty and 'FinalResidual' in successful_df.columns:
        # Convert to numeric, handling 'N/A' values
        residuals = pd.to_numeric(successful_df['FinalResidual'], errors='coerce')
        valid_data = successful_df[residuals.notna()]
        
        if not valid_data.empty:
            ax3.semilogy(valid_data['Reynolds'], residuals.dropna(), 'ro-', linewidth=2, markersize=8)
            ax3.set_xlabel('Reynolds Number')
            ax3.set_ylabel('Final Residual')
            ax3.set_title('Convergence Quality vs Reynolds Number')
            ax3.grid(True, alpha=0.3)
    
    # Plot 4: Performance Summary
    performance_data = {
        'Total Cases': len(df),
        'Successful': len(df[df['Status'] == 'SUCCESS']),
        'Failed': len(df[df['Status'] == 'FAILED']),
        'Poor Convergence': len(df[df['Status'] == 'CONVERGED_POOR'])
    }
    
    bars = ax4.bar(performance_data.keys(), performance_data.values(), 
                   color=['blue', 'green', 'red', 'orange'])
    ax4.set_title('Simulation Results Summary')
    ax4.set_ylabel('Number of Cases')
    
    # Add value labels on bars
    for bar in bars:
        height = bar.get_height()
        ax4.text(bar.get_x() + bar.get_width()/2., height,
                f'{int(height)}', ha='center', va='bottom')
    
    plt.tight_layout()
    
    # Save plot
    summary_plot_path = Path(results_dir) / "parametric_study_summary.png"
    plt.savefig(summary_plot_path, dpi=150, bbox_inches='tight')
    plt.close()
    
    print(f"Generated summary plot: {summary_plot_path}")
    return summary_plot_path

def generate_html_report(results_dir):
    """Generate comprehensive HTML report"""
    
    summary_file = Path(results_dir) / "summary.csv"
    if not summary_file.exists():
        print(f"Error: Summary file not found: {summary_file}")
        return
    
    df = pd.read_csv(summary_file)
    
    # Generate summary statistics
    total_cases = len(df)
    successful_cases = len(df[df['Status'] == 'SUCCESS'])
    success_rate = (successful_cases / total_cases * 100) if total_cases > 0 else 0
    
    # Calculate average runtime for successful cases
    successful_df = df[df['Status'] == 'SUCCESS']
    avg_runtime = successful_df['Runtime'].mean() if not successful_df.empty else 0
    
    # Generate HTML report
    html_content = f"""
<!DOCTYPE html>
<html>
<head>
    <title>OpenFOAM Parametric Study Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; }}
        .header {{ background-color: #f0f0f0; padding: 20px; border-radius: 5px; }}
        .metrics {{ display: flex; justify-content: space-around; margin: 20px 0; }}
        .metric {{ text-align: center; padding: 15px; background-color: #e8f4f8; border-radius: 5px; }}
        .metric h3 {{ margin: 0; color: #2c5f7f; }}
        .metric p {{ font-size: 24px; font-weight: bold; margin: 5px 0; color: #1a4a60; }}
        table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
        th, td {{ padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }}
        th {{ background-color: #4CAF50; color: white; }}
        tr:nth-child(even) {{ background-color: #f2f2f2; }}
        .success {{ color: green; font-weight: bold; }}
        .failed {{ color: red; font-weight: bold; }}
        .warning {{ color: orange; font-weight: bold; }}
        .timestamp {{ color: #666; font-style: italic; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🌊 OpenFOAM Parametric Study Report</h1>
        <p class="timestamp">Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        <p><strong>Study:</strong> Cavity Flow - Reynolds Number Parametric Analysis</p>
    </div>
    
    <div class="metrics">
        <div class="metric">
            <h3>Total Cases</h3>
            <p>{total_cases}</p>
        </div>
        <div class="metric">
            <h3>Success Rate</h3>
            <p>{success_rate:.1f}%</p>
        </div>
        <div class="metric">
            <h3>Successful Cases</h3>
            <p>{successful_cases}</p>
        </div>
        <div class="metric">
            <h3>Avg Runtime</h3>
            <p>{avg_runtime:.1f}s</p>
        </div>
    </div>
    
    <h2>📊 Results Summary</h2>
    <img src="parametric_study_summary.png" alt="Parametric Study Summary" style="width: 100%; max-width: 1000px;">
    
    <h2>📋 Detailed Results</h2>
    <table>
        <tr>
            <th>Reynolds Number</th>
            <th>Status</th>
            <th>Runtime (s)</th>
            <th>Final Residual</th>
            <th>Convergence Quality</th>
        </tr>
"""
    
    # Add table rows
    for _, row in df.iterrows():
        status_class = "success" if row['Status'] == 'SUCCESS' else "failed" if row['Status'] == 'FAILED' else "warning"
        
        # Determine convergence quality
        convergence_quality = "Excellent"
        if row['FinalResidual'] != 'N/A':
            try:
                residual_val = float(row['FinalResidual'])
                if residual_val > 0.001:
                    convergence_quality = "Poor"
                elif residual_val > 0.0001:
                    convergence_quality = "Good"
            except:
                convergence_quality = "Unknown"
        
        html_content += f"""
        <tr>
            <td>{row['Reynolds']}</td>
            <td><span class="{status_class}">{row['Status']}</span></td>
            <td>{row['Runtime']}</td>
            <td>{row['FinalResidual']}</td>
            <td>{convergence_quality}</td>
        </tr>
"""
    
    html_content += """
    </table>
    
    <h2>🔧 System Information</h2>
    <ul>
        <li><strong>Solver:</strong> simpleFoam (SIMPLE algorithm)</li>
        <li><strong>Mesh:</strong> 20x20 structured grid</li>
        <li><strong>Convergence Criteria:</strong> Residual < 1e-3</li>
        <li><strong>Boundary Conditions:</strong> Moving lid cavity</li>
    </ul>
    
    <h2>📈 CI/CD Integration</h2>
    <p>This report demonstrates:</p>
    <ul>
        <li>✅ Automated parametric studies</li>
        <li>✅ Quality validation and convergence checking</li>
        <li>✅ Performance monitoring and metrics collection</li>
        <li>✅ Structured reporting for DevOps integration</li>
    </ul>
    
    <footer style="margin-top: 50px; padding: 20px; background-color: #f9f9f9; border-radius: 5px;">
        <p><em>Report generated by OpenFOAM CI/CD Pipeline</em></p>
        <p>For questions or issues, contact the DevOps team.</p>
    </footer>
</body>
</html>
"""
    
    # Save HTML report
    report_path = Path(results_dir) / "parametric_study_report.html"
    with open(report_path, 'w') as f:
        f.write(html_content)
    
    print(f"Generated HTML report: {report_path}")
    return report_path

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 generate-report.py <results_directory>")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    
    if not Path(results_dir).exists():
        print(f"Error: Results directory not found: {results_dir}")
        sys.exit(1)
    
    print(f"Generating comprehensive report for: {results_dir}")
    
    # Generate summary plots
    generate_summary_plots(results_dir)
    
    # Generate HTML report
    generate_html_report(results_dir)
    
    print("Report generation completed successfully!")
    print(f"Open {results_dir}/parametric_study_report.html to view the report")

if __name__ == "__main__":
    main()