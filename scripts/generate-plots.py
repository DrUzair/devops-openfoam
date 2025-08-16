#!/usr/bin/env python3
"""
OpenFOAM Results Visualization Script
Generates plots for cavity flow simulation results
"""

import os
import sys
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from pathlib import Path

def plot_residuals(case_dir, reynolds_num, output_dir):
    """Plot convergence residuals"""
    residuals_file = Path(case_dir) / "postProcessing/residuals/0/residuals.dat"
    
    if not residuals_file.exists():
        print(f"Warning: Residuals file not found: {residuals_file}")
        return False
    
    # Read residuals data
    try:
        data = pd.read_csv(residuals_file, sep='\s+', header=None, skiprows=1)
        data.columns = ['Time', 'Ux', 'Uy', 'p']
        
        # Create residuals plot
        fig, ax = plt.subplots(1, 1, figsize=(10, 6))
        ax.semilogy(data['Time'], data['Ux'], 'b-', label='Ux', linewidth=2)
        ax.semilogy(data['Time'], data['Uy'], 'r-', label='Uy', linewidth=2)
        ax.semilogy(data['Time'], data['p'], 'g-', label='p', linewidth=2)
        
        ax.set_xlabel('Iteration')
        ax.set_ylabel('Residual')
        ax.set_title(f'Convergence History - Re = {reynolds_num}')
        ax.legend()
        ax.grid(True, alpha=0.3)
        ax.set_ylim(1e-6, 1)
        
        # Save plot
        plot_path = Path(output_dir) / f"residuals_Re{reynolds_num}.png"
        plt.savefig(plot_path, dpi=150, bbox_inches='tight')
        plt.close()
        
        print(f"Generated residuals plot: {plot_path}")
        return True
        
    except Exception as e:
        print(f"Error plotting residuals: {e}")
        return False

def plot_velocity_profile(case_dir, reynolds_num, output_dir):
    """Plot velocity profile along centerline"""
    # This is a simplified version - in practice you'd use OpenFOAM postprocessing
    # For demo purposes, we'll create a placeholder plot
    
    try:
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
        
        # Placeholder velocity profiles (would normally extract from OpenFOAM results)
        y = np.linspace(0, 1, 50)
        
        # Approximate cavity flow profiles for different Reynolds numbers
        if reynolds_num <= 100:
            u_profile = np.sin(np.pi * y) * 0.8
        else:
            u_profile = np.sin(np.pi * y) * (1.0 - np.exp(-reynolds_num/1000))
        
        v_profile = np.zeros_like(y)  # Simplified
        
        # U velocity profile
        ax1.plot(u_profile, y, 'b-', linewidth=2, label=f'Re = {reynolds_num}')
        ax1.set_xlabel('U velocity')
        ax1.set_ylabel('Y coordinate')
        ax1.set_title('U Velocity Profile - Vertical Centerline')
        ax1.grid(True, alpha=0.3)
        ax1.legend()
        
        # V velocity profile  
        ax2.plot(v_profile, y, 'r-', linewidth=2, label=f'Re = {reynolds_num}')
        ax2.set_xlabel('V velocity')
        ax2.set_ylabel('Y coordinate')
        ax2.set_title('V Velocity Profile - Vertical Centerline')
        ax2.grid(True, alpha=0.3)
        ax2.legend()
        
        plt.tight_layout()
        
        # Save plot
        plot_path = Path(output_dir) / f"velocity_profile_Re{reynolds_num}.png"
        plt.savefig(plot_path, dpi=150, bbox_inches='tight')
        plt.close()
        
        print(f"Generated velocity profile plot: {plot_path}")
        return True
        
    except Exception as e:
        print(f"Error plotting velocity profile: {e}")
        return False

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 generate-plots.py <case_directory> <reynolds_number>")
        sys.exit(1)
    
    case_dir = sys.argv[1]
    reynolds_num = int(sys.argv[2])
    
    # Create plots directory
    output_dir = Path(case_dir) / "plots"
    output_dir.mkdir(exist_ok=True)
    
    print(f"Generating plots for case: {case_dir}, Re = {reynolds_num}")
    
    # Generate plots
    success_residuals = plot_residuals(case_dir, reynolds_num, output_dir)
    success_velocity = plot_velocity_profile(case_dir, reynolds_num, output_dir)
    
    if success_residuals and success_velocity:
        print(f"Successfully generated all plots for Re = {reynolds_num}")
        return 0
    else:
        print(f"Some plots failed for Re = {reynolds_num}")
        return 1

if __name__ == "__main__":
    sys.exit(main())