#!/usr/bin/env python3
"""
Demo script showing how the dynamic URL feature works
This simulates the app's URL input functionality
"""

import json
import time
from datetime import datetime

class DynamicURLDemo:
    """Demo of the dynamic URL input feature"""
    
    def __init__(self):
        self.saved_urls = []
        self.current_url = None
        
    def simulate_app_interface(self):
        """Simulate the app's URL input interface"""
        print("🎯 ZipRoute Dynamic URL Input Demo")
        print("=" * 50)
        print("This simulates the URL input feature in your app")
        print()
        
        while True:
            print("📱 App Interface Simulation:")
            print("1. Enter Backend URL")
            print("2. Test Connection")
            print("3. Save Configuration")
            print("4. View Saved URLs")
            print("5. Quick URL Templates")
            print("6. Auto Detect Backend")
            print("7. Exit")
            print()
            
            choice = input("Choose an option (1-7): ").strip()
            
            if choice == "1":
                self._enter_url()
            elif choice == "2":
                self._test_connection()
            elif choice == "3":
                self._save_configuration()
            elif choice == "4":
                self._view_saved_urls()
            elif choice == "5":
                self._quick_url_templates()
            elif choice == "6":
                self._auto_detect()
            elif choice == "7":
                print("👋 Goodbye!")
                break
            else:
                print("❌ Invalid option. Please try again.")
            
            print("\n" + "="*50 + "\n")
    
    def _enter_url(self):
        """Simulate entering a URL"""
        print("📝 Enter Backend URL")
        print("Examples:")
        print("  - https://abc123.ngrok.io")
        print("  - http://192.168.1.100:8000")
        print("  - https://delivery-w97o.onrender.com")
        print()
        
        url = input("Enter URL: ").strip()
        if url:
            self.current_url = url
            print(f"✅ URL entered: {url}")
            print(f"🔍 URL Type: {self._get_url_type(url)}")
        else:
            print("❌ No URL entered")
    
    def _test_connection(self):
        """Simulate testing connection"""
        if not self.current_url:
            print("❌ No URL to test. Please enter a URL first.")
            return
        
        print(f"🧪 Testing connection to: {self.current_url}")
        print("⏳ Testing...")
        time.sleep(2)  # Simulate network delay
        
        # Simulate different connection results
        if "ngrok.io" in self.current_url:
            print("✅ Connection successful! (ngrok tunnel)")
        elif "192.168." in self.current_url:
            print("✅ Connection successful! (local network)")
        elif "onrender.com" in self.current_url:
            print("✅ Connection successful! (production)")
        elif "localhost" in self.current_url:
            print("✅ Connection successful! (local development)")
        else:
            print("❌ Connection failed! (simulated)")
    
    def _save_configuration(self):
        """Simulate saving configuration"""
        if not self.current_url:
            print("❌ No URL to save. Please enter a URL first.")
            return
        
        if self.current_url not in self.saved_urls:
            self.saved_urls.append(self.current_url)
            print(f"✅ Configuration saved: {self.current_url}")
            print("💾 URL added to favorites")
        else:
            print("ℹ️ URL already saved")
    
    def _view_saved_urls(self):
        """Simulate viewing saved URLs"""
        if not self.saved_urls:
            print("📭 No saved URLs yet")
            return
        
        print("💾 Saved URLs:")
        for i, url in enumerate(self.saved_urls, 1):
            url_type = self._get_url_type(url)
            print(f"  {i}. {url} ({url_type})")
        
        print("\nOptions:")
        print("1. Use a saved URL")
        print("2. Delete a saved URL")
        print("3. Back to main menu")
        
        choice = input("Choose option: ").strip()
        
        if choice == "1":
            try:
                index = int(input("Enter URL number: ")) - 1
                if 0 <= index < len(self.saved_urls):
                    self.current_url = self.saved_urls[index]
                    print(f"✅ Using URL: {self.current_url}")
                else:
                    print("❌ Invalid URL number")
            except ValueError:
                print("❌ Invalid input")
        elif choice == "2":
            try:
                index = int(input("Enter URL number to delete: ")) - 1
                if 0 <= index < len(self.saved_urls):
                    deleted_url = self.saved_urls.pop(index)
                    print(f"🗑️ Deleted: {deleted_url}")
                else:
                    print("❌ Invalid URL number")
            except ValueError:
                print("❌ Invalid input")
    
    def _quick_url_templates(self):
        """Simulate quick URL templates"""
        templates = [
            ("Production", "https://delivery-w97o.onrender.com"),
            ("ngrok.io", "https://"),
            ("Local 101", "http://192.168.0.101:8000"),
            ("Emulator", "http://10.0.2.2:8000"),
            ("Localhost", "http://localhost:8000"),
        ]
        
        print("⚡ Quick URL Templates:")
        for i, (name, url) in enumerate(templates, 1):
            print(f"  {i}. {name}: {url}")
        
        try:
            choice = int(input("Choose template (1-5): ")) - 1
            if 0 <= choice < len(templates):
                self.current_url = templates[choice][1]
                print(f"✅ Template selected: {self.current_url}")
            else:
                print("❌ Invalid template number")
        except ValueError:
            print("❌ Invalid input")
    
    def _auto_detect(self):
        """Simulate auto-detection"""
        print("🔍 Auto-detecting backend...")
        print("⏳ Scanning network...")
        time.sleep(3)  # Simulate detection time
        
        # Simulate different detection results
        detected_urls = [
            "http://192.168.0.101:8000",
            "https://abc123.ngrok.io",
            "https://delivery-w97o.onrender.com"
        ]
        
        print("🎯 Detected backends:")
        for i, url in enumerate(detected_urls, 1):
            print(f"  {i}. {url} ({self._get_url_type(url)})")
        
        try:
            choice = int(input("Choose detected backend (1-3): ")) - 1
            if 0 <= choice < len(detected_urls):
                self.current_url = detected_urls[choice]
                print(f"✅ Auto-detected: {self.current_url}")
            else:
                print("❌ Invalid choice")
        except ValueError:
            print("❌ Invalid input")
    
    def _get_url_type(self, url):
        """Get URL type for display"""
        if "ngrok.io" in url:
            return "ngrok Tunnel"
        elif "onrender.com" in url:
            return "Production (Render)"
        elif "192.168." in url:
            return "Local Network"
        elif "10.0.2.2" in url:
            return "Android Emulator"
        elif "localhost" in url or "127.0.0.1" in url:
            return "Local Development"
        else:
            return "Custom URL"

def main():
    """Main demo function"""
    demo = DynamicURLDemo()
    demo.simulate_app_interface()

if __name__ == "__main__":
    main()
