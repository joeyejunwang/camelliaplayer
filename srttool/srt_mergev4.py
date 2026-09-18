#!/usr/bin/env python3

import sys
import re
from pathlib import Path

def parse_srt_file(filepath: Path) -> list[dict]:
    """Parse SRT file reliably, handling variable spacing and line structures."""
    with open(filepath, 'r', encoding='utf-8-sig') as f:
        lines = f.readlines()
    
    entries = []
    i = 0
    total_lines = len(lines)
    
    while i < total_lines:
        line = lines[i].strip()
        
        # Match subtitle block index
        if re.match(r'^\d+$', line):
            index = int(line)
            
            # Check for the timestamp line right after the index line
            if i + 1 < total_lines:
                time_line = lines[i + 1].strip()
                time_match = re.match(r'(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})', time_line)
                
                if time_match:
                    start_time = time_match.group(1)
                    end_time = time_match.group(2)
                    
                    text_lines = []
                    j = i + 2
                    
                    # Collect text until an empty line
                    while j < total_lines:
                        next_line = lines[j].strip()
                        if not next_line:
                            break
                        text_lines.append(next_line)
                        j += 1
                    
                    full_text = ' '.join(text_lines)
                    
                    if not re.search(r'opensubtitles', full_text, re.IGNORECASE) and len(full_text.strip()) > 14:
                        entries.append({
                            'file_line_start': i + 1,
                            'file_line_end': j,
                            'index': index,
                            'start_time': start_time,
                            'end_time': end_time,
                            'text_lines': text_lines,
                            'full_text': full_text
                        })
                    
                    i = j
                    continue
        i += 1
        
    return entries


def ends_with_period(text: str) -> bool:
    """Check if text ends with terminal punctuation."""
    return text.rstrip().endswith(('.', '?', '!'))


def find_merged_groups(entries: list[dict]) -> list[list[dict]]:
    """Group entries sequentially until terminal punctuation is encountered."""
    groups = []
    current_group = []
    
    for entry in entries:
        current_group.append(entry)
        if ends_with_period(entry['full_text']):
            groups.append(current_group)
            current_group = []
            
    if current_group:
        groups.append(current_group)
        
    return groups


def clean_text(text: str) -> str:
    """Remove HTML tags, dialogue dashes, and normalize whitespace."""
    # Strip HTML tags like <i>, <font color="...">
    text = re.sub(r'<[^>]+>', '', text)

    # Remove dialogue dashes/hyphens
    text = re.sub(r'(?:^|\s machinery)-\s*', ' ', text)
    text = re.sub(r'(?:^|\s)-\s*', ' ', text)

    # Normalize whitespace
    text = re.sub(r'\s+', ' ', text).strip()

    return text


def merge_entries(entries: list[dict]) -> dict:
    """Merge a collection of consecutive subtitle blocks into a single sentence."""
    if not entries:
        return None
        
    raw_text = ' '.join(' '.join(e['text_lines']) for e in entries)
    full_text = clean_text(raw_text)
    
    # Capitalize starting character
    if full_text:
        full_text = full_text[0].upper() + full_text[1:]
        
    # Append terminal period if sentence ending is missing
    # if full_text and not full_text.endswith(('.', '?', '!')):
    #     full_text += '.'
        
    if not full_text:
        return None

    return {
        'index': entries[0]['index'],
        'start_time': entries[0]['start_time'],
        'end_time': entries[-1]['end_time'],
        'text': full_text,
        'line_range': f"{entries[0]['file_line_start']}-{entries[-1]['file_line_end']}"
    }


def main():
    raw_path = r"D:\New folder\oworkings\srt\02.srt"
    save_path = r"D:\New folder\oworkings\srt\02_merged.srt"

    filepath = Path(raw_path).resolve()

    if not filepath.exists():
        print(f"Error: File not found at {filepath}")
        sys.exit(1)
        
    entries = parse_srt_file(filepath)
    
    if not entries:
        print(f"Error: No subtitle entries found in {filepath}")
        sys.exit(1)
        
    groups = find_merged_groups(entries)
    merged_entries = [m for group in groups if (m := merge_entries(group))]
    
    with open(save_path, 'w', encoding='utf-8') as f:
        for i, merged in enumerate(merged_entries, 1):
            f.write(f"{i}\n")
            f.write(f"{merged['start_time']} --> {merged['end_time']}\n")
            f.write(f"{merged['text']}\n\n")

    print(f"Successfully processed {len(entries)} subtitles into {len(merged_entries)} merged SRT sentences.")
    print(f"Output saved to: {save_path}")


if __name__ == "__main__":
    main()