import gtts
from gtts import gTTS
from IPython.display import Audio, display
import os

def convert_hindi_to_speech_and_play_colab(hindi_text_input):
    """
    Converts given Hindi text directly into Hindi speech and plays it in Google Colab.
    """
    try:
        print(f"Converting Hindi text to speech: '{hindi_text_input}'")

       
        tts = gTTS(text=hindi_text_input, lang='hi', slow=False)

       
        audio_file_name = "colab_hindi_speech.mp3"
        tts.save(audio_file_name)   
        print(f"Audio saved to {audio_file_name}")

       
        print("Playing audio in Colab...")
        display(Audio(audio_file_name, autoplay=True)) 
        

       
    except Exception as e:
        print(f"An error occurred: {e}")
        print("Please ensure you have an active internet connection, as gTTS requires it.")
user_input_hindi = input("कृपया हिंदी में वह टेक्स्ट दर्ज करें जिसे आप हिंदी भाषण में बदलना चाहते हैं: ")


convert_hindi_to_speech_and_play_colab(user_input_hindi)