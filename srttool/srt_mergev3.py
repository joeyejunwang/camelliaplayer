import sys
import re
from pathlib import Path

# Maximum length threshold for merged text before forcing a split
MAX_GROUP_CHARS = 120


def parse_srt_file(filepath: str) -> list[dict]:
    """Parse SRT file and return list of entries with their line numbers."""
    with open(filepath, 'r', encoding='utf-8-sig') as f:
        lines = f.readlines()
    
    entries = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        
        # Check if line is a number (index)
        if re.match(r'^\d+$', line):
            index = int(line)
            # Next line should be time
            if i + 1 < len(lines):
                time_line = lines[i + 1].strip()
                time_match = re.match(r'(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})', time_line)
                if time_match:
                    start_time = time_match.group(1)
                    end_time = time_match.group(2)
                    
                    # Collect all text lines until empty line or next index
                    text_lines = []
                    j = i + 2
                    while j < len(lines):
                        next_line = lines[j].strip()
                        if next_line == '' or re.match(r'^\d+$', next_line):
                            break
                        text_lines.append(next_line)
                        j += 1
                    
                    entries.append({
                        'file_line_start': i + 1,
                        'file_line_end': j,
                        'index': index,
                        'start_time': start_time,
                        'end_time': end_time,
                        'text_lines': text_lines,
                        'full_text': ' '.join(text_lines)
                    })
                    i = j
                    continue
        i += 1
    
    return entries


def is_sentence_end(text: str) -> bool:
    """Check if text ends with standard sentence-ending punctuation (. ! ?) or quotes/brackets."""
    text = text.rstrip()
    if not text:
        return False
    return bool(re.search(r'[.!?]["\'”’)]*$', text))


def find_merged_groups(entries: list[dict]) -> list[list[dict]]:
    """Find groups of entries to merge based on sentence punctuation and length caps."""
    groups = []
    current_group = []
    current_length = 0
    
    for entry in entries:
        text = entry['full_text']
        current_group.append(entry)
        current_length += len(text)
        
        # Split if entry finishes a sentence OR if merged text exceeds character limit
        if is_sentence_end(text) or current_length >= MAX_GROUP_CHARS:
            groups.append(current_group)
            current_group = []
            current_length = 0
    
    # Don't forget any remaining entries
    if current_group:
        groups.append(current_group)
    
    return groups


def merge_entries(entries: list[dict]) -> dict:
    """Merge multiple entries into one."""
    if not entries:
        return None
    
    merged_text = []
    for entry in entries:
        merged_text.extend(entry['text_lines'])
    
    # Join text and clean formatting/HTML tags
    full_text = ' '.join(merged_text)
    full_text = re.sub(r'<[^>]+>', '', full_text)
    full_text = full_text.replace('\n', ' ').replace('  ', ' ').replace('- ', '').rstrip()
    
    # Capitalize first letter
    if full_text:
        full_text = full_text[0].upper() + full_text[1:]
    
    return {
        'index': entries[0]['index'],
        'start_time': entries[0]['start_time'],
        'end_time': entries[-1]['end_time'],
        'text': full_text,
        'line_range': f"{entries[0]['file_line_start']}-{entries[-1]['file_line_end']}"
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: python srt_mergev2.py <file.srt>")
        sys.exit(1)
    
    filepath = sys.argv[1]
    input_path = Path(filepath)
    output_path = input_path.with_name(f"{input_path.stem}fix.srt")
    
    # Parse file
    entries = parse_srt_file(filepath)

    if not entries:
        print(f"Error: No subtitle entries found in {filepath}")
        sys.exit(1)
    
    # Find groups to merge
    groups = find_merged_groups(entries)
    
    # Merge each group
    merged_entries = [merge_entries(group) for group in groups if group]
    
    # Write output to SRT file
    with open(output_path, 'w', encoding='utf-8') as f:
        for i, merged in enumerate(merged_entries, 1):
            if not merged:
                continue
            f.write(f"{i}\n")
            f.write(f"{merged['start_time']} --> {merged['end_time']}\n")
            text = merged['text'].replace('\n', ' ').replace('  ', ' ').rstrip()
            f.write(f"{text}\n\n")

    print(f"Saved merged subtitles to: {output_path}")


if __name__ == "__main__":
    main()

# python srt_mergev3.py /d/Working/1.srt