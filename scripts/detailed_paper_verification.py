import pdfplumber
import re

pdf_path = r"c:\fyp\version-u\fyp_app\lib\accident_prediction\dataset\research_paper_33.pdf"

try:
    with pdfplumber.open(pdf_path) as pdf:
        print("="*70)
        print("DETAILED PAPER [33] DATASET VERIFICATION")
        print("="*70 + "\n")
        
        # Extract all text
        full_text = ""
        for page in pdf.pages:
            full_text += page.extract_text() + "\n"
        
        # Search for dataset-related sections
        search_terms = [
            ("Dataset", "Dataset"),
            ("Data:", "Data"),
            ("Sample", "Samples"),
            ("3,084", "3,084 samples"),
            ("3084", "3084 samples"),
            ("2,604", "Class distribution"),
            ("2,197", "Class distribution"),
            ("1,927", "Class distribution"),
            ("Slow", "Slow class"),
            ("Normal driving", "Normal class"),
            ("Aggressive", "Aggressive class"),
        ]
        
        print("🔍 SEARCHING FOR KEY TERMS IN PAPER:\n")
        for search_term, description in search_terms:
            if search_term.lower() in full_text.lower():
                print(f"  ✅ Found: {description}")
                # Try to find context
                idx = full_text.lower().find(search_term.lower())
                if idx > 0:
                    context_start = max(0, idx - 100)
                    context_end = min(len(full_text), idx + 200)
                    context = full_text[context_start:context_end].replace('\n', ' ')
                    print(f"     Context: ...{context}...\n")
            else:
                print(f"  ❌ Not found: {description}")
        
        # Extract numbers that might be sample counts
        print("\n" + "="*70)
        print("NUMERIC PATTERNS (Potential Sample Counts):")
        print("="*70)
        numbers = re.findall(r'(\d+[,.]?\d*)\s*(?:samples?|records?|data points?)', full_text, re.IGNORECASE)
        for num in set(numbers):
            print(f"  • {num}")
        
        # Look for the IV. DATASET section
        print("\n" + "="*70)
        print("SEARCHING FOR 'IV. DATASET' SECTION:")
        print("="*70)
        
        if "IV." in full_text:
            idx = full_text.find("IV.")
            section = full_text[idx:idx+2000]
            print(section[:1500])
        
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
