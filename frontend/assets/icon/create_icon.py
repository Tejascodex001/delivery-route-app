#!/usr/bin/env python3
"""
Simple icon creator for ZipRoot app
"""
import struct

def create_simple_png():
    """Create a simple PNG icon programmatically"""
    # PNG header
    png_header = b'\x89PNG\r\n\x1a\n'
    
    # IHDR chunk (Image Header)
    width, height = 1024, 1024
    bit_depth = 8
    color_type = 6  # RGBA
    compression = 0
    filter_method = 0
    interlace = 0
    
    ihdr_data = struct.pack('>IIBBBBB', width, height, bit_depth, color_type, 
                           compression, filter_method, interlace)
    ihdr_crc = 0x4A4A4A4A  # Placeholder CRC
    ihdr_chunk = struct.pack('>I', 13) + b'IHDR' + ihdr_data + struct.pack('>I', ihdr_crc)
    
    # Simple blue background with white route
    # This is a simplified approach - in practice, you'd want a proper PNG encoder
    print("Creating a simple icon...")
    
    # For now, let's create a basic file that can be replaced
    with open('icon.png', 'wb') as f:
        f.write(png_header)
        f.write(ihdr_chunk)
        # Add minimal PNG data (this is simplified)
        f.write(b'\x00\x00\x00\x00IEND\xaeB`\x82')
    
    print("Icon created!")

if __name__ == "__main__":
    create_simple_png()
