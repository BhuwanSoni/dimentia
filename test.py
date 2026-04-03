import joblib
import numpy as np
import pandas as pd
from datetime import datetime
 
 
# =============================================================================
# DISPLAY HELPERS
# =============================================================================
 
def _header(title):
    print("\n" + "=" * 58)
    print(f"  {title}")
    print("=" * 58)
 
def _section(title):
    print(f"\n--- {title} ---")
 
def _get_int(prompt, min_val, max_val):
    """Keep asking until valid integer in [min_val, max_val]."""
    while True:
        try:
            val = int(input(f"  {prompt}: ").strip())
            if min_val <= val <= max_val:
                return val
            print(f"  ⚠  Please enter a number between {min_val} and {max_val}.")
        except ValueError:
            print("  ⚠  Please enter a whole number.")
 
def _get_choice(prompt, valid):
    """Keep asking until user picks one of valid (case-insensitive)."""
    while True:
        val = input(f"  {prompt} ({'/'.join(valid)}): ").strip().upper()
        if val in [v.upper() for v in valid]:
            return val
        print(f"  ⚠  Please enter one of: {'/'.join(valid)}")
 
 
# =============================================================================
# PART 1 — DEMOGRAPHIC INFORMATION
# =============================================================================
 
def get_demographic_input():
    """
    Collects: AGE, GENDER, YEARS_OF_EDUCATION, EDUCATION (1-5), SES (1-5)
    Encoding matches the training dataset exactly.
    """
    _header("PART 1 — Background Information")
 
    user_data = {}
 
    # AGE
    _section("Age")
    user_data['AGE'] = _get_int("Enter your age (40–100)", 40, 100)
 
    # GENDER  (dataset: 0=Female, 1=Male)
    _section("Gender")
    g = _get_choice("Enter gender", ["M", "F"])
    user_data['GENDER'] = 1 if g == 'M' else 0
 
    # YEARS_OF_EDUCATION — raw years (dataset uses actual years e.g. 12, 16, 25)
    _section("Years of Education")
    print("  Examples: No schooling=0, High school=12, Bachelor=16,")
    print("            Master=18, PhD=21+")
    user_data['YEARS_OF_EDUCATION'] = _get_int("Total years of formal education (0–30)", 0, 30)
 
    # EDUCATION — 1–5 categorical scale
    _section("Education Level")
    print("  1 = Less than high school")
    print("  2 = High school graduate")
    print("  3 = Some college / diploma")
    print("  4 = College / bachelor's degree")
    print("  5 = Postgraduate (Master's / PhD)")
    user_data['EDUCATION'] = _get_int("Enter education level (1–5)", 1, 5)
 
    # SES — 1–5 scale (1=highest, 5=lowest, matching OASIS convention)
    _section("Socioeconomic Status (SES)")
    print("  1 = Highest  (wealthy / senior professional)")
    print("  2 = Upper-middle")
    print("  3 = Middle")
    print("  4 = Lower-middle")
    print("  5 = Lowest")
    user_data['SES'] = _get_int("Enter SES level (1–5)", 1, 5)
 
    # Summary
    print("\n  ✅ Background information recorded.")
    return user_data
 
 
# =============================================================================
# PART 2 — COGNITIVE SCREENING TEST (MMSE estimation)
# =============================================================================
 
def conduct_cognitive_test():
    """
    Simplified MMSE-style screening test.
 
    Scoring (max 14 pts):
      Orientation  3 pts  — year, season, day
      Calculation  1 pt   — 100 minus 7
      Attention    1 pt   — WORLD backwards
      Language     2 pts  — naming objects, repeating phrase
      Memory reg.  3 pts  — immediate recall of 3 words
      Recall       3 pts  — delayed recall of 3 words
      Drawing      1 pt   — self-reported ability
 
    Raw score mapped to MMSE range 15–30 (matching dataset).
    Higher MMSE = better cognition.
    """
    _header("PART 2 — Cognitive Screening Test")
    print("  Please answer each question as best you can.")
    print("  There are no trick questions.\n")
 
    score = 0
    words = ["APPLE", "TABLE", "PENNY"]
 
    # --- Immediate memory registration (3 pts) ---
    _section("Memory")
    print(f"  Please READ and REMEMBER these 3 words:")
    print(f"\n      👉  {' — '.join(words)}\n")
    input("  Press Enter when you have memorised them...")
    print("\n" * 4)
 
    # 1. Orientation — Year (1 pt)
    _section("Orientation")
    try:
        ans = int(input("  Q1. What year is it? ").strip())
        if ans == datetime.now().year:
            score += 1
            print("      ✓")
        else:
            print(f"      ✗  (expected {datetime.now().year})")
    except ValueError:
        print("      ✗  Invalid")
 
    # 2. Orientation — Season (1 pt)
    month = datetime.now().month
    season_map = {
        (3, 4, 5): "spring",
        (6, 7, 8): "summer",
        (9, 10, 11): "autumn",
        (12, 1, 2): "winter"
    }
    current_season = next(s for months, s in season_map.items() if month in months)
    ans = input("  Q2. What season is it? ").strip().lower()
    if ans in [current_season, "fall"]:
        score += 1
        print("      ✓")
    else:
        print(f"      ✗  (expected {current_season})")
 
    # 3. Orientation — Day of week (1 pt)
    today = datetime.now().strftime('%A').lower()
    ans = input("  Q3. What day of the week is it? ").strip().lower()
    if today in ans or ans in today:
        score += 1
        print("      ✓")
    else:
        print(f"      ✗  (expected {today.capitalize()})")
 
    # 4. Calculation — Serial 7 (1 pt)
    _section("Calculation")
    ans = input("  Q4. What is 100 minus 7? ").strip()
    if ans == "93":
        score += 1
        print("      ✓")
    else:
        print("      ✗  (expected 93)")
 
    # 5. Attention — WORLD backwards (1 pt)
    _section("Attention")
    ans = input("  Q5. Spell the word WORLD backwards: ").strip().lower()
    if ans == "dlrow":
        score += 1
        print("      ✓")
    else:
        print("      ✗  (expected DLROW)")
 
    # 6. Language — Naming 2 objects (1 pt)
    _section("Language")
    ans = input("  Q6. Name any 2 everyday objects (e.g. pen, clock): ").strip()
    if len(ans.split()) >= 2:
        score += 1
        print("      ✓")
    else:
        print("      ✗  (name at least 2 objects)")
 
    # 7. Language — Phrase repetition (1 pt)
    ans = input('  Q7. Repeat this phrase exactly: "No ifs, ands, or buts": ').strip().lower()
    if "no ifs" in ans and "buts" in ans:
        score += 1
        print("      ✓")
    else:
        print("      ✗  (phrase not matched)")
 
    # 8. Immediate word recall — 3 pts (asked right after registration)
    _section("Immediate Word Recall")
    print("  Q8. What were the 3 words you were asked to remember?")
    recall_immediate = input("  Your answer: ").upper()
    immediate_recalled = sum(w in recall_immediate for w in words)
    score += immediate_recalled
    print(f"      Recalled {immediate_recalled}/3 words immediately (+{immediate_recalled} pts)")
 
    # 9. Distraction task before delayed recall
    _section("Short Distraction Task")
    print("  Q9. Count backwards from 20 to 1 aloud (press Enter when done).")
    input("  Press Enter when finished...")
 
    # 10. Delayed word recall — 3 pts
    _section("Delayed Word Recall")
    print("  Q10. Can you still recall those 3 words from earlier?")
    recall_delayed = input("  Your answer: ").upper()
    delayed_recalled = sum(w in recall_delayed for w in words)
    score += delayed_recalled
    print(f"       Recalled {delayed_recalled}/3 words after delay (+{delayed_recalled} pts)")
 
    # 11. Drawing / Visuospatial — self-reported (1 pt)
    _section("Visuospatial Ability")
    print("  Q11. Can you draw a simple clock face with hands showing 3 o'clock?")
    ans = _get_choice("  Answer", ["Y", "N"])
    if ans == "Y":
        score += 1
        print("      ✓")
 
    # --- Map raw score (0–14) → MMSE range 15–30 ---
    max_score = 14
    mmse = int(15 + (score / max_score) * 15)
    mmse = max(15, min(mmse, 30))
 
    print(f"\n  Raw cognitive score : {score}/{max_score}")
    print(f"  Estimated MMSE      : {mmse}/30")
 
    # Interpretation hint
    if mmse >= 27:
        print("  Interpretation      : Normal cognition")
    elif mmse >= 21:
        print("  Interpretation      : Mild cognitive concern")
    elif mmse >= 18:
        print("  Interpretation      : Moderate cognitive concern")
    else:
        print("  Interpretation      : Significant cognitive concern")
 
    return mmse
 
 
# =============================================================================
# BUILD MODEL INPUT
# =============================================================================
 
def build_input(user_data, mmse, feature_names):
    """
    Builds a single-row DataFrame in the exact column order
    expected by the trained model.
    Expected features: AGE, GENDER, YEARS_OF_EDUCATION, SES, EDUCATION, MMSE
    """
    row = {
        'AGE':                user_data['AGE'],
        'GENDER':             user_data['GENDER'],
        'YEARS_OF_EDUCATION': user_data['YEARS_OF_EDUCATION'],
        'SES':                user_data['SES'],
        'EDUCATION':          user_data['EDUCATION'],
        'MMSE':               mmse,
    }
 
    df = pd.DataFrame([row])
 
    # Validate all expected features are present
    missing = [f for f in feature_names if f not in df.columns]
    if missing:
        raise ValueError(
            f"Missing features: {missing}\n"
            "Check that questionnaire covers all model features."
        )
 
    return df[feature_names]  # enforce training column order
 
 
# =============================================================================
# PREDICTION & DISPLAY
# =============================================================================
 
def predict_and_display(model, df_input, threshold, user_data, mmse):
    """
    Runs prediction, applies tuned threshold, prints tiered risk result
    with personalised contributing factor commentary.
    """
    prob  = model.predict_proba(df_input)[0][1]
    risk  = round(prob * 100, 1)
    pred  = 1 if prob >= threshold else 0
 
    _header("ASSESSMENT RESULT")
 
    # Risk meter visual
    filled = int(risk / 5)
    bar    = "█" * filled + "░" * (20 - filled)
    print(f"\n  Risk Score  : {risk}%")
    print(f"  [{bar}]")
    print(f"  Threshold   : {threshold:.2f}  |  MMSE used: {mmse}/30")
 
    # Risk level
    if pred == 0:
        level = "🟢 LOW RISK"
        advice = ("No significant cognitive concern detected. "
                  "Maintain regular physical activity, a balanced diet, "
                  "and stay socially and mentally engaged.")
    elif prob < 0.70:
        level = "🟡 MODERATE RISK"
        advice = ("Some cognitive risk indicators are present. "
                  "Consider scheduling a check-up with your doctor "
                  "and discuss a formal cognitive assessment.")
    else:
        level = "🔴 HIGH RISK"
        advice = ("Multiple significant risk factors detected. "
                  "Please consult a neurologist or geriatric specialist "
                  "as soon as possible for a comprehensive evaluation.")
 
    print(f"\n  Risk Level  : {level}")
 
    # Personalised factor commentary
    print("\n  Contributing factors in your assessment:")
 
    if mmse < 24:
        print(f"    ⚠  MMSE score ({mmse}/30) is below normal range (≥27)")
    else:
        print(f"    ✓  MMSE score ({mmse}/30) is within normal range")
 
    if user_data['AGE'] >= 75:
        print(f"    ⚠  Age ({user_data['AGE']}) — risk increases after 75")
    else:
        print(f"    ✓  Age ({user_data['AGE']}) — not yet a high-risk age group")
 
    edu_years = user_data['YEARS_OF_EDUCATION']
    if edu_years < 12:
        print(f"    ⚠  Fewer years of education ({edu_years}) associated with higher risk")
    else:
        print(f"    ✓  Education level ({edu_years} years) is a protective factor")
 
    if user_data['SES'] >= 4:
        print(f"    ⚠  Lower SES (level {user_data['SES']}) may limit access to care")
    else:
        print(f"    ✓  SES level ({user_data['SES']}) — no major concern")
 
    print(f"\n  Advice      : {advice}")
 
    print("\n" + "-" * 58)
    print("  ⚠  DISCLAIMER: This is a screening tool only.")
    print("     It is NOT a clinical diagnosis. Always consult a")
    print("     qualified healthcare professional for evaluation.")
    print("=" * 58)
 
    return pred
 
 
# =============================================================================
# MAIN
# =============================================================================
 
def main():
    _header("DEMENTIA RISK ASSESSMENT SYSTEM")
    print("  This tool estimates your dementia risk using a machine")
    print("  learning model trained on 92,000+ patient records.")
    print("  It takes approximately 5 minutes to complete.")
 
    # --- Load artifacts ---
    print("\n  Loading model...")
    try:
        model         = joblib.load("dementia_model.pkl")
        feature_names = joblib.load("feature_names.pkl")
        try:
            threshold = joblib.load("threshold.pkl")
            print(f"  ✅ Tuned threshold loaded: {threshold:.2f}")
        except FileNotFoundError:
            threshold = 0.43  # matches your new model's tuned threshold
            print(f"  ⚠  threshold.pkl not found — using default: {threshold}")
        print(f"  ✅ Features: {feature_names}")
    except FileNotFoundError as e:
        print(f"\n  ❌ Model file not found: {e}")
        print("     Run training_model_fixed.py first to generate artifacts.")
        return
 
    # --- Run assessment ---
    user_data = get_demographic_input()
    mmse      = conduct_cognitive_test()
 
    # --- Predict ---
    try:
        df_input = build_input(user_data, mmse, feature_names)
    except ValueError as e:
        print(f"\n  ❌ Input error: {e}")
        return
 
    predict_and_display(model, df_input, threshold, user_data, mmse)
 
    # --- Run again option ---
    print()
    again = _get_choice("Run another assessment", ["Y", "N"])
    if again == "Y":
        main()
    else:
        print("\n  Thank you for using the Dementia Risk Assessment System.")
        print("  Stay healthy! 👋\n")
 
 
if __name__ == "__main__":
    main()