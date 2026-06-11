import pdfplumber
import sys

pdf_path = r"c:\fyp\version-u\fyp_app\lib\accident_prediction\dataset\research_paper_33.pdf"

try:
    with pdfplumber.open(pdf_path) as pdf:
        print(f"✅ PDF opened successfully")
        print(f"Total pages: {len(pdf.pages)}\n")
        
        # Extract text from all pages
        full_text = ""
        for i, page in enumerate(pdf.pages):
            full_text += page.extract_text() + "\n"
        
        # Search for dataset information
        print("="*70)
        print("DATASET VERIFICATION FROM PAPER [33]")
        print("="*70)
        
        checks = [
            ("6,728 samples", ["6,728", "6728"]),
            ("Samsung Galaxy S21", ["Samsung", "Galaxy", "S21"]),
            ("50 Hz sampling rate", ["50 Hz", "50Hz", "50 hz"]),
            ("Driving classes", ["Slow", "Normal", "Aggressive"]),
            ("Accelerometer data", ["accelerometer", "Acc_X", "Acc_Y", "Acc_Z"]),
            ("Gyroscope data", ["gyroscope", "Gyro_X", "Gyro_Y", "Gyro_Z"]),
        ]
        
        for check_name, keywords in checks:
            found = any(kw in full_text for kw in keywords)
            status = "✅" if found else "❌"
            print(f"{status} {check_name}")
        
        # Extract data section
        print("\n" + "="*70)
        print("DATA SECTION FROM PAPER:")
        print("="*70)
        
        lines = full_text.split('\n')
        
        # Find lines containing "Data:" or dataset info
        for i, line in enumerate(lines):
            if any(keyword in line.lower() for keyword in ['data:', 'dataset:', '6,728', '6728', 'samsung galaxy']):
                start = max(0, i-1)
                end = min(len(lines), i+15)
                section_text = '\n'.join(lines[start:end])
                if len(section_text.strip()) > 20:
                    print(section_text)
                    print("-" * 70)
        
        print("\n✅ PDF verification complete!")
        
except FileNotFoundError:
    print(f"❌ File not found: {pdf_path}")
    sys.exit(1)
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
